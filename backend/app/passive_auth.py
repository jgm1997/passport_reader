"""
Passive Authentication for ePassport chips (ICAO 9303 Part 11).

Proves that data read from a chip was signed by the issuing country:
    1. the SOD's signature is valid for its Document Signer (DS) certificate.
    2. the DS certificate was issued by a trusted Country Signing CA (CSCA).
    3. every data group sent to us hashes to the value listed in the SOD.
"""

from __future__ import annotations

import hashlib
import hmac
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any, ClassVar

from asn1crypto import algos, core, parser
from cryptography import x509
from cryptography.exceptions import InvalidSignature

from app.cms_verify import (
    HASHES,
    CmsError,
    encapsulated_content,
    load_signed_data,
    signer_and_certificate,
    verify_signer,
)
from app.revocation import CrlStore, RevocationStatus
from app.trust_store import TrustStore, country_of

LDS_SECURITY_OBJECT = "2.23.136.1.1.1"


# --- ASN.1 structures (ICAO 9303 Part 10) ---
class DataGroupHash(core.Sequence):
    _fields: ClassVar[list[tuple[Any, ...]]] = [
        ("number", core.Integer),
        ("hash", core.OctetString),
    ]


class DataGroupHashes(core.SequenceOf):
    _child_spec = DataGroupHash


class LdsVersionInfo(core.Sequence):
    _fields: ClassVar[list[tuple[Any, ...]]] = [
        ("lds_version", core.PrintableString),
        ("unicode_version", core.PrintableString),
    ]


class LdsSecurityObject(core.Sequence):
    _fields: ClassVar[list[tuple[Any, ...]]] = [
        ("version", core.Integer),
        ("hash_algorithm", algos.DigestAlgorithm),
        ("data_group_hashes", DataGroupHashes),
        ("lds_version_info", LdsVersionInfo, {"optional": True}),
    ]


# --- Result ---
@dataclass
class PassiveAuthResult:
    valid: bool = False
    issuing_country: str | None = None
    hash_algorithm: str | None = None
    # Only filled when valid: these hashes are vouched for by the issuing country.
    authenticated_hashes: dict[int, bytes] = field(default_factory=dict)
    verified_data_groups: list[int] = field(default_factory=list)
    failures: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


# --- Main entry point ---
def verify_passive_auth(
    sod: bytes,
    data_groups: dict[int, bytes],
    trust: TrustStore,
    crls: CrlStore | None = None,
    require_crl: bool = False,
    now: datetime | None = None,
) -> PassiveAuthResult:
    now = now or datetime.now(UTC)
    result = PassiveAuthResult()

    # 0. Parse. Anything malformed ends here, with a reason instead of a crash.
    try:
        signed_data = load_signed_data(_unwrap_ef_sod(sod))
        lds_bytes = encapsulated_content(signed_data, LDS_SECURITY_OBJECT)
        lds = LdsSecurityObject.load(lds_bytes, strict=True)
        signer, dsc = signer_and_certificate(signed_data)
        hash_name = lds["hash_algorithm"]["algorithm"].native
        expected = {
            h["number"].native: h["hash"].native for h in lds["data_group_hashes"]
        }
    except (CmsError, ValueError, TypeError, KeyError, IndexError) as e:
        result.failures.append(f"malformed SOD: {e}")
        return result

    if hash_name not in HASHES:
        result.failures.append(f"unsupported hash algorithm: {hash_name}")
        return result
    result.hash_algorithm = hash_name

    # 1. Is the SOD really signed by its Document Signer?
    try:
        verify_signer(signer, lds_bytes, LDS_SECURITY_OBJECT, dsc)
    except InvalidSignature:
        result.failures.append(
            "SOD signature does not match the Document Signer certificate"
        )
    except (CmsError, ValueError, KeyError) as e:
        result.failures.append(f"SOD signature could not be verified: {e}")

    # 2. Was the Document Signer issued by a CSCA we trust?
    csca = trust.find_issuer(dsc)
    if csca is None:
        result.failures.append("Document Signer was not issued by any trusted CSCA")
    else:
        dsc_country, csca_country = country_of(dsc.subject), country_of(csca.subject)
        if dsc_country != csca_country:
            result.failures.append(
                "Document Signer and CSCA belong to different countries"
            )
        result.issuing_country = csca_country
        for cert, label in ((dsc, "Document signer"), (csca, "CSCA")):
            if not cert.not_valid_before_utc <= now <= cert.not_valid_after_utc:
                result.failures.append(
                    f"{label} certificate is outside its validity period"
                )
        _check_revocation(result, dsc, csca, crls, require_crl, now)

    # 3. Do the data groups we received match the signed hashes?
    for number, content in sorted(data_groups.items()):
        want = expected.get(number)
        if want is None:
            result.failures.append(f"DG{number} is not listed in the SOD")
            continue
        got = hashlib.new(hash_name, content).digest()
        if hmac.compare_digest(got, want):
            result.verified_data_groups.append(number)
        else:
            result.failures.append(f"DG{number} hash mismatch: the data was altered")

    if 1 not in result.verified_data_groups:
        result.failures.append("DG1 (the holder's details) was not verified")

    result.valid = not result.failures
    if result.valid:
        result.authenticated_hashes = expected
    return result


# --- Steps ---
def _unwrap_ef_sod(sod: bytes) -> bytes:
    class_, _method, tag, _header, contents, _trailer = parser.parse(sod, strict=True)
    if class_ == 1 and tag == 23:
        return contents
    return sod


def _check_revocation(
    result: PassiveAuthResult,
    dsc: x509.Certificate,
    csca: x509.Certificate,
    crls: CrlStore | None,
    require_crl: bool,
    now: datetime,
) -> None:
    country = country_of(csca.subject)
    if crls is None:
        status = RevocationStatus.UNKNOWN
    else:
        status = crls.status(dsc, csca, now)

    if status is RevocationStatus.REVOKED:
        result.failures.append("Document Signer certificate has been revoked")
        return
    problem = {
        RevocationStatus.STALE: f"the CRL for {country} is out of date",
        RevocationStatus.UNKNOWN: f"no trusted CRL available for {country}",
    }.get(status)
    if problem:
        # Policy decision: fail closed (require_crl) or fail open with a warning
        (result.failures if require_crl else result.warnings).append(problem)

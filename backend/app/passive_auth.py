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

from asn1crypto import algos, cms, core, parser
from asn1crypto import x509 as asn1_x509
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa

from app.trust_store import TrustStore, country_of

LDS_SECURITY_OBJECT = "2.23.136.1.1.1"

_HASHES = {
    "sha1": hashes.SHA1,
    "sha224": hashes.SHA224,
    "sha256": hashes.SHA256,
    "sha384": hashes.SHA384,
    "sha512": hashes.SHA512,
}


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
class PassiveAuthError(Exception):
    """The SOD is malformed or uses something this server doesn't support."""


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
    now: datetime | None = None,
) -> PassiveAuthResult:
    now = now or datetime.now(UTC)
    result = PassiveAuthResult()

    # 0. Parse. Anything malformed ends here, with a reason instead of a crash.
    try:
        signed_data = _load_signed_data(sod)
        lds_bytes, lds = _load_lds_security_object(signed_data)
        signer = _single_signer(signed_data)
        dsc = _find_document_signer(signed_data, signer)
        hash_name = lds["hash_algorithm"]["algorithm"].native
        expected = {
            h["number"].native: h["hash"].native for h in lds["data_group_hashes"]
        }
    except (PassiveAuthError, ValueError, TypeError, KeyError, IndexError) as e:
        result.failures.append(f"malformed SOD: {e}")
        return result

    if hash_name not in _HASHES:
        result.failures.append(f"unsupported hash algorithm: {hash_name}")
        return result
    result.hash_algorithm = hash_name

    # 1. Is the SOD really signed by its Document Signer?
    try:
        _check_signed_attributes(signer, lds_bytes)
        _verify_signature(dsc.public_key(), signer)
    except InvalidSignature:
        result.failures.append(
            "SOD signature does not match the Document Signer certificate"
        )
    except (PassiveAuthError, ValueError, KeyError) as e:
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

    result.warnings.append("certificate revocation (CRL) was not checked")
    result.valid = not result.failures
    if result.valid:
        result.authenticated_hashes = expected
    return result


# --- Steps ---
def _load_signed_data(sod: bytes) -> cms.SignedData:
    class_, _method, tag, _header, contents, _trailer = parser.parse(sod, strict=True)
    if class_ == 1 and tag == 23:  # EF.SOD wraps the CMS in [APPLICATION 23] (0x77)
        sod = contents
    info = cms.ContentInfo.load(sod, strict=True)
    if info["content_type"].native != "signed_data":
        raise PassiveAuthError("not a CMS SignedData structure")
    return info["content"]


def _load_lds_security_object(
    signed_data: cms.SignedData,
) -> tuple[bytes, LdsSecurityObject]:
    encap = signed_data["encap_content_info"]
    if encap["content_type"].dotted != LDS_SECURITY_OBJECT:
        raise PassiveAuthError("SOD does not contain an LDS Security Object")
    lds_bytes = encap["content"].native
    if not isinstance(lds_bytes, bytes):
        raise PassiveAuthError("LDS Security Object is missing")
    return lds_bytes, LdsSecurityObject.load(lds_bytes, strict=True)


def _single_signer(signed_data: cms.SignedData) -> cms.SignerInfo:
    signers = signed_data["signer_infos"]
    if len(signers) != 1:
        raise PassiveAuthError(f"expected exactly 1 signer, found {len(signers)}")
    return signers[0]


def _find_document_signer(
    signed_data: cms.SignedData, signer: cms.SignerInfo
) -> x509.Certificate:
    certificates = signed_data["certificates"]
    if isinstance(certificates, core.Void) or len(certificates) == 0:
        raise PassiveAuthError("SOD contains no Document Signer certificate")

    sid = signer["sid"]
    for choice in certificates:
        cert = choice.chosen
        if not isinstance(cert, asn1_x509.Certificate):
            continue
        if sid.name == "issuer_and_serial_number":
            match = (
                cert.issuer == sid.chosen["issuer"]
                and cert.serial_number == sid.chosen["serial_number"].native
            )
        else:  # subject_key_identifier
            match = cert.key_identifier == sid.chosen.native
        if match:
            try:
                return x509.load_der_x509_certificate(cert.dump())
            except ValueError as e:
                raise PassiveAuthError(
                    f"Document Signer certificate can't be loaded (e.g. explicit EC parameters): {e}"
                ) from e
    raise PassiveAuthError("Document Signer certificate not found in SOD")


def _check_signed_attributes(signer: cms.SignerInfo, lds_bytes: bytes) -> None:
    attrs = signer["signed_attrs"]
    if isinstance(attrs, core.Void) or len(attrs) == 0:
        raise PassiveAuthError("SOD has no signed attributes")

    found = {a["type"].native: a["values"] for a in attrs}
    if len(found) != len(attrs):
        raise PassiveAuthError("duplicate signed attributes")

    content_type, digest = found.get("content_type"), found.get("message_digest")
    if not content_type or not digest or len(content_type) != 1 or len(digest) != 1:
        raise PassiveAuthError("content-type or message-digest attribute missing")
    if content_type[0].dotted != LDS_SECURITY_OBJECT:
        raise PassiveAuthError("signed content-type attribute is wrong")

    digest_name = signer["digest_algorithm"]["algorithm"].native
    if digest_name not in _HASHES:
        raise PassiveAuthError(f"unsupported digest algorithm: {digest_name}")
    actual = hashlib.new(digest_name, lds_bytes).digest()
    if not hmac.compare_digest(digest[0].native, actual):
        raise PassiveAuthError("message digest does not match the LDS Security Object")


def _verify_signature(public_key, signer: cms.SignerInfo) -> None:
    # The signature covers the DER of the signed attributes re-tagged as a SET (0x31),
    # not the [0] IMPLICIT tag (0xA0) they carry inside SignerInfo (RFC 5652, 5.4).
    data = b"\x31" + signer["signed_attrs"].dump()[1:]
    signature = signer["signature"].native
    sig_algo = signer["signature_algorithm"]
    kind = sig_algo.signature_algo

    try:
        hash_name = sig_algo.hash_algo  # e.g. "sha256" for sha256_rsa / ecdsa / pss
    except ValueError:
        hash_name = signer["digest_algorithm"]["algorithm"].native
    if hash_name not in _HASHES:
        raise PassiveAuthError(f"unsupported hash: {hash_name}")
    digest = _HASHES[hash_name]()

    if kind == "rsassa_pkcs1v15" and isinstance(public_key, rsa.RSAPublicKey):
        public_key.verify(signature, data, padding.PKCS1v15(), digest)
    elif kind == "rsassa_pss" and isinstance(public_key, rsa.RSAPublicKey):
        params = sig_algo["parameters"]
        mgf_hash = params["mask_gen_algorithm"]["parameters"]["algorithm"].native
        if mgf_hash not in _HASHES:
            raise PassiveAuthError(f"unsupported MGF1 hash: {mgf_hash}")
        public_key.verify(
            signature,
            data,
            padding.PSS(
                mgf=padding.MGF1(_HASHES[mgf_hash]()),
                salt_length=params["salt_length"].native,
            ),
            digest,
        )
    elif kind == "ecdsa" and isinstance(public_key, ec.EllipticCurvePublicKey):
        public_key.verify(signature, data, ec.ECDSA(digest))
    else:
        raise PassiveAuthError(f"unsupported signature algorithm: {kind}")

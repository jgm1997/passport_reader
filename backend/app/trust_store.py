"""Trusted Country Signing CA (CSCA) certificates: the roots of passport trust."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from typing import Any, ClassVar

from asn1crypto import core
from asn1crypto import x509 as asn1_x509
from cryptography import x509
from cryptography.exceptions import InvalidSignature, UnsupportedAlgorithm
from cryptography.x509.oid import NameOID

from app.cms_verify import (
    CmsError,
    encapsulated_content,
    load_signed_data,
    signer_and_certificate,
    verify_signer,
)
from app.ec_keys import public_key_of, verify_certificate_signature

CSCA_MASTER_LIST = "2.23.136.1.1.2"


class MasterListError(Exception):
    """A master list is malformed or can't be trusted."""


class _CertificateSet(core.SetOf):
    _child_spec = asn1_x509.Certificate


class CscaMasterList(core.Sequence):
    _fields: ClassVar[list[tuple[Any, ...]]] = [
        ("version", core.Integer),
        ("cert_list", _CertificateSet),
    ]


def country_of(name: x509.Name) -> str | None:
    values = name.get_attributes_for_oid(NameOID.COUNTRY_NAME)
    return str(values[0].value).upper() if values else None


def issued_by(cert: x509.Certificate, issuer: x509.Certificate):
    """True if `issuer`'key really signed `cert` (names AND signature must match)."""
    if cert.issuer != issuer.subject:
        return False
    try:
        verify_certificate_signature(cert, public_key_of(issuer))
        return True
    except (ValueError, TypeError, InvalidSignature, UnsupportedAlgorithm):
        return False


def _is_ca(cert: x509.Certificate) -> bool:
    try:
        return cert.extensions.get_extension_for_class(x509.BasicConstraints).value.ca
    except (x509.ExtensionNotFound, ValueError):
        return False


def load_certificates_from_file(file: Path) -> list[x509.Certificate]:
    data = file.read_bytes()
    if data.lstrip().startswith(b"-----BEGIN"):
        return x509.load_pem_x509_certificates(data)
    if file.suffix.lower() in {"der", ".cer", ".crt"}:
        return [x509.load_der_x509_certificate(data)]
    return []


def load_certificates(path: str | Path) -> list[x509.Certificate]:
    """Loads every PEM/DER certificate file in a folder."""
    return [
        cert
        for file in sorted(Path(path).iterdir())
        if file.is_file()
        for cert in load_certificates_from_file(file)
    ]


class TrustStore:
    def __init__(self, cscas: list[x509.Certificate], skipped: int = 0):
        # Only real CAs may act as trust anchors.
        self._cscas = [c for c in cscas if _is_ca(c)]
        self._skipped = skipped  # unreadable certificates dropped from master lists

    def __len__(self) -> int:
        return len(self._cscas)

    @property
    def certificates(self) -> list[x509.Certificate]:
        return list(self._cscas)

    @property
    def skipped(self) -> int:
        return self._skipped

    @property
    def countries(self) -> set[str]:
        return {c for c in (country_of(cert.subject) for cert in self._cscas) if c}

    def find_issuer(self, cert: x509.Certificate) -> x509.Certificate | None:
        """
        Returns the trusted CSCA whose key signed `cert`, or None.
        Several CSCAs can share a name (key rollover), so we try each one.
        """
        return next((csca for csca in self._cscas if issued_by(cert, csca)), None)

    @classmethod
    def from_directory(
        cls,
        path: str | Path,
        ml_anchors: list[x509.Certificate] | None = None,
        allow_unverified_master_lists: bool = False,
    ) -> TrustStore:
        certs: list[x509.Certificate] = []
        skipped = 0
        for file in sorted(Path(path).iterdir()):
            if file.suffix.lower() == ".ml":
                if ml_anchors is None and not allow_unverified_master_lists:
                    raise MasterListError(
                        f"{file.name}: refusing an unverified master list. Put the signer's "
                        "root certificate in anchors/ (or set ALLOW_UNVERIFIED_MASTER_LISTS=1)"
                    )
                try:
                    ml_certs, ml_skipped = load_master_list(file.read_bytes(), ml_anchors)
                    certs += ml_certs
                    skipped += ml_skipped
                except MasterListError as e:
                    raise MasterListError(f"{file.name}: {e}") from e
            elif file.is_file():
                certs += load_certificates_from_file(file)
        return cls(certs, skipped)


def load_master_list(
    data: bytes, anchors: list[x509.Certificate] | None, now: datetime | None = None
) -> tuple[list[x509.Certificate], int]:
    """
    Extracts CSCA certificates from an ICAO CSCA Master List (.ml).

    With `anchors`, the list's signature must verify and its signer must have been
    issued by one of the anchors. With `anchors=None` nothing is verified, so you
    are trusting the channel you downloaded the file from.
    """
    skipped = 0
    try:
        signed = load_signed_data(data)
        content = encapsulated_content(signed, CSCA_MASTER_LIST)
        if anchors is not None:
            _verify_master_list_signer(
                signed, content, anchors, now or datetime.now(UTC)
            )
        master_list = CscaMasterList.load(content, strict=True)
        entries = list(master_list["cert_list"])
    except (CmsError, ValueError, TypeError, KeyError) as e:
        raise MasterListError(f"invalid master list: {e}") from e

    certs = []
    for entry in entries:
        try:
            certs.append(x509.load_der_x509_certificate(entry.dump()))
        except ValueError:
            skipped += 1  # malformed certificate (e.g. non-positive serial): ignore it, keep the rest
    return certs, skipped


def _verify_master_list_signer(
    signed, content: bytes, anchors: list[x509.Certificate], now: datetime
) -> None:
    signer, signer_cert = signer_and_certificate(signed)
    try:
        verify_signer(signer, content, CSCA_MASTER_LIST, signer_cert)
    except InvalidSignature as e:
        raise MasterListError("master list signature is invalid") from e
    if not signer_cert.not_valid_before_utc <= now <= signer_cert.not_valid_after_utc:
        raise MasterListError(
            "master list signer certificate is outside its validity period"
        )
    if not any(issued_by(signer_cert, anchor) for anchor in anchors):
        raise MasterListError("master list was not signed by a trusted anchor")

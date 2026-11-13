"""Trusted Country Signing CA (CSCA) certificates: the roots of passport trust."""

from __future__ import annotations

from pathlib import Path
from typing import Any, ClassVar

from asn1crypto import cms, core
from asn1crypto import x509 as asn1_x509
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.x509.oid import NameOID

CSCA_MASTER_LIST = "2.23.136.1.1.2"


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


def _is_ca(cert: x509.Certificate) -> bool:
    try:
        return cert.extensions.get_extension_for_class(x509.BasicConstraints).value.ca
    except (x509.ExtensionNotFound, ValueError):
        return False


class TrustStore:
    def __init__(self, cscas: list[x509.Certificate]):
        # Only real CAs may act as trust anchors.
        self._cscas = [c for c in cscas if _is_ca(c)]

    def __len__(self) -> int:
        return len(self._cscas)

    @property
    def countries(self) -> set[str]:
        return {c for c in (country_of(cert.subject) for cert in self._cscas) if c}

    def find_issuer(self, cert: x509.Certificate) -> x509.Certificate | None:
        """Returns the trusted CSCA whose key signed `cert`, or None."""
        for csca in self._cscas:
            if csca.subject != cert.subject:
                continue
            try:
                cert.verify_directly_issued_by(csca)
                return csca
            except (ValueError, TypeError, InvalidSignature):
                continue  # Same name, different key (e.g. CSCA rollover): keep looking.
        return None

    @classmethod
    def from_directory(cls, path: str | Path) -> TrustStore:
        certs: list[x509.Certificate] = []
        for file in sorted(Path(path).iterdir()):
            data = file.read_bytes()
            suffix = file.suffix.lower()
            if suffix == ".ml":
                certs += load_master_list(data)
            elif data.lstrip().startswith(b"-----BEGIN"):
                certs += x509.load_pem_x509_certificates(data)
            elif suffix in {".der", ".cer", ".crt"}:
                certs.append(x509.load_der_x509_certificate(data))
        return cls(certs)


def load_master_list(data: bytes) -> list[x509.Certificate]:
    """
    Extracts CSCA certificates from an ICAO CSCA Master List (.ml).

    WARNING: this does not verify the master list's own signature, so you are
    trusting the channel you downloaded it from.
    """
    info = cms.ContentInfo.load(data)
    encap = info["content"]["encap_content_info"]
    if encap["content_type"].dotted != CSCA_MASTER_LIST:
        raise ValueError("not a CSCA Master List")
    master_list = CscaMasterList.load(encap["content"].native)

    certs = []
    for entry in master_list["cert_list"]:
        try:
            certs.append(x509.load_der_x509_certificate(entry.dump()))
        except ValueError:
            continue  # e.g. explicit EC curve parameters, unsupported by `cryptography`
    return certs

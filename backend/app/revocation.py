"""Certificate Revocation Lists: has a country withdrawn a Document Signer?"""

from datetime import datetime
from enum import Enum
from pathlib import Path

from cryptography import x509
from cryptography.exceptions import UnsupportedAlgorithm

from app.ec_keys import public_key_of


class RevocationStatus(Enum):
    GOOD = "good"  # a fresh, trusted CRL exists and doesn't list the certificate
    REVOKED = "revoked"  # a trusted CRL lists the certificate
    STALE = "stale"  # trusted CRLs exist, but the newest one has expired
    UNKNOWN = "unknown"  # no CRL from this issuer that we can trust


class CrlStore:
    def __init__(self, crls: list[x509.CertificateRevocationList]):
        self._crls = list(crls)

    def __len__(self) -> int:
        return len(self._crls)

    @classmethod
    def from_directory(cls, path: str | Path) -> "CrlStore":
        folder = Path(path)
        if not folder.is_dir():
            return cls([])

        crls = []
        for file in sorted(folder.iterdir()):
            data = file.read_bytes()
            try:
                if data.lstrip().startswith(b"-----BEGIN"):
                    crls.append(x509.load_pem_x509_crl(data))
                elif file.suffix.lower() in {".crl", ".der"}:
                    crls.append(x509.load_der_x509_crl(data))
            except ValueError:
                continue  # unreadable CRL: ingore it rather than crash the server
        return cls(crls)

    def status(
        self, cert: x509.Certificate, issuer: x509.Certificate, now: datetime
    ) -> RevocationStatus:
        # Only CRLs really signed by the issueing CSCA count. A forged CRL is ignored.
        trusted = [
            crl
            for crl in self._crls
            if crl.issuer == issuer.subject and _signed_by(crl, issuer)
        ]
        if not trusted:
            return RevocationStatus.UNKNOWN
        if any(
            crl.get_revoked_certificate_by_serial_number(cert.serial_number) is not None
            for crl in trusted
        ):
            return RevocationStatus.REVOKED
        newest = max(trusted, key=lambda crl: crl.last_update_utc)
        if newest.next_update_utc is None or now > newest.next_update_utc:
            return RevocationStatus.STALE
        return RevocationStatus.GOOD


def _signed_by(crl: x509.CertificateRevocationList, issuer: x509.Certificate) -> bool:
    try:
        return crl.is_signature_valid(public_key_of(issuer))
    except (TypeError, ValueError, UnsupportedAlgorithm):
        return False

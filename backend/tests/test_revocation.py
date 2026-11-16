from datetime import UTC, datetime, timedelta

from app.passive_auth import verify_passive_auth
from app.revocation import CrlStore, RevocationStatus
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization


def _cert(path):
    return x509.load_pem_x509_certificate(path.read_bytes())


def _crl(utopia, revoked=(), next_update_in=timedelta(days=30), key_file="csca.key"):
    """A CRL in Utopia's CSCA's name, signed with `key_file`."""
    key = serialization.load_pem_private_key(
        (utopia / key_file).read_bytes(), password=None
    )
    now = datetime.now(UTC)
    builder = (
        x509.CertificateRevocationListBuilder()
        .issuer_name(_cert(utopia / "csca.pem").subject)
        .last_update(now - timedelta(days=1))
        .next_update(now + next_update_in)
    )
    for serial in revoked:
        builder = builder.add_revoked_certificate(
            x509.RevokedCertificateBuilder()
            .serial_number(serial)
            .revocation_date(now - timedelta(hours=1))
            .build()
        )
    return builder.sign(key, hashes.SHA256())


def test_revoked_document_signer_is_rejected(passport, trust, utopia):
    sod, dgs = passport
    dsc_serial = _cert(utopia / "dsc.pem").serial_number
    result = verify_passive_auth(
        sod, dgs, trust, crls=CrlStore([_crl(utopia, revoked=[dsc_serial])])
    )
    assert not result.valid
    assert "Document Signer certificate has been revoked" in result.failures


def test_fresh_crl_without_our_signer_is_good(passport, trust, utopia):
    sod, dgs = passport
    result = verify_passive_auth(sod, dgs, trust, crls=CrlStore([_crl(utopia)]))
    assert result.valid
    assert not any("CRL" in w for w in result.warnings)


def test_crl_signed_with_the_wrong_key_is_ignored(utopia):
    dsc = _cert(utopia / "dsc.pem")
    forged = _crl(utopia, revoked=[dsc.serial_number], key_file="dsc.key")
    status = CrlStore([forged]).status(
        dsc, _cert(utopia / "csca.pem"), datetime.now(UTC)
    )
    assert status is RevocationStatus.UNKNOWN


def test_stale_crl_warns_by_default_and_fails_when_required(passport, trust, utopia):
    sod, dgs = passport
    crls = CrlStore([_crl(utopia, next_update_in=-timedelta(hours=1))])

    lenient = verify_passive_auth(sod, dgs, trust, crls=crls)
    assert lenient.valid
    assert any("out of date" in w for w in lenient.warnings)

    strict = verify_passive_auth(sod, dgs, trust, crls=crls, require_crl=True)
    assert not strict.valid
    assert any("out of date" in f for f in strict.failures)


def test_missing_crl_fails_when_required(passport, trust):
    sod, dgs = passport
    result = verify_passive_auth(sod, dgs, trust, crls=CrlStore([]), require_crl=True)
    assert not result.valid
    assert any("no trusted CRL" in f for f in result.failures)

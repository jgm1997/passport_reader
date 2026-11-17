"""Germany's (and other countries') keys use Brainpool curves with explicit parameters."""

from app.passive_auth import verify_passive_auth
from app.trust_store import TrustStore, load_master_list
from cryptography import x509


def _cert(path):
    return x509.load_pem_x509_certificate(path.read_bytes())


def test_passport_from_explicit_curve_country_verifies(explicit_passport, explicitland):
    sod, dgs = explicit_passport
    result = verify_passive_auth(
        sod, dgs, TrustStore.from_directory(explicitland / "trust")
    )
    assert result.valid, result.failures
    assert result.issuing_country == "BP"


def test_explicit_curve_signatures_are_still_checked(explicit_passport, explicitland):
    sod, dgs = explicit_passport
    tampered = bytearray(sod)
    tampered[-5] ^= 0x01  # inside the ECDSA signature value
    result = verify_passive_auth(
        bytes(tampered), dgs, TrustStore.from_directory(explicitland / "trust")
    )
    assert not result.valid
    assert any("signature" in f for f in result.failures)


def test_master_list_signed_with_explicit_curve_is_accepted(
    explicit_master_list, explicitland
):
    """The exact situation of the German master list."""
    cscas, skipped = load_master_list(
        explicit_master_list, anchors=[_cert(explicitland / "csca.pem")]
    )
    assert skipped == 0
    assert TrustStore(cscas).countries == {"UT"}

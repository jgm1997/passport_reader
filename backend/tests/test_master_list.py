import pytest
from app.passive_auth import verify_passive_auth
from app.trust_store import MasterListError, TrustStore, load_master_list
from cryptography import x509


def _cert(path):
    return x509.load_pem_x509_certificate(path.read_bytes())


def test_verified_master_list_lets_us_trust_utopia(master_list, neverland, passport):
    cscas = load_master_list(master_list, anchors=[_cert(neverland / "anchor.pem")])
    trust = TrustStore(cscas)
    assert trust.countries == {"UT"}

    sod, dgs = passport
    assert verify_passive_auth(sod, dgs, trust).valid


def test_master_list_signed_by_someone_else_is_refused(master_list, utopia):
    with pytest.raises(MasterListError, match="trusted anchor"):
        load_master_list(master_list, anchors=[_cert(utopia / "csca.pem")])


def test_tampered_master_list_is_refused(master_list, neverland):
    tampered = bytearray(master_list)
    tampered[-5] ^= 0x01  # inside the signature value
    with pytest.raises(MasterListError):
        load_master_list(bytes(tampered), anchors=[_cert(neverland / "anchor.pem")])


def test_unverified_master_lists_are_refused_by_default(master_list, tmp_path):
    (tmp_path / "list.ml").write_bytes(master_list)
    with pytest.raises(MasterListError, match="unverified"):
        TrustStore.from_directory(tmp_path)


def test_unverified_master_lists_can_be_allowed_explicitly(master_list, tmp_path):
    (tmp_path / "list.ml").write_bytes(master_list)
    trust = TrustStore.from_directory(tmp_path, allow_unverified_master_lists=True)
    assert trust.countries == {"UT"}

import pytest
from app import trust_store
from app.passive_auth import verify_passive_auth
from app.trust_store import MasterListError, TrustStore, load_master_list
from cryptography import x509


def _cert(path):
    return x509.load_pem_x509_certificate(path.read_bytes())


def test_verified_master_list_lets_us_trust_utopia(master_list, neverland, passport):
    cscas, skipped = load_master_list(
        master_list, anchors=[_cert(neverland / "anchor.pem")]
    )
    assert skipped == 0
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


def test_one_broken_entry_does_not_break_the_whole_list(master_list, monkeypatch):
    # master_list: your fixture's .ml bytes (rename to match your conftest)
    expected, skipped = load_master_list(master_list, None)
    assert skipped == 0

    real_loader = trust_store.x509.load_der_x509_certificate
    calls = 0

    def fails_once(data):
        nonlocal calls
        calls += 1
        if calls == 1:
            raise ValueError(
                "non-positive serial number"
            )  # what future cryptography will do
        return real_loader(data)

    monkeypatch.setattr(trust_store.x509, "load_der_x509_certificate", fails_once)
    certs, skipped = load_master_list(master_list, None)

    assert skipped == 1
    assert len(certs) == len(expected) - 1

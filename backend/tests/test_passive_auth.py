from datetime import UTC, datetime

from app.passive_auth import verify_passive_auth
from app.trust_store import TrustStore


def test_genuine_passport_is_valid(passport, trust):
    sod, dgs = passport
    result = verify_passive_auth(sod, dgs, trust)
    assert result.valid, result.failures
    assert result.issuing_country == "UT"
    assert result.verified_data_groups == [1, 2]
    assert set(result.authenticated_hashes) == {1, 2}


def test_altered_data_group_is_rejected(passport, trust):
    sod, dgs = passport
    result = verify_passive_auth(sod, {**dgs, 1: dgs[1] + b"!"}, trust)
    assert not result.valid
    assert any("DG1 hash mismatch" in f for f in result.failures)
    assert result.authenticated_hashes == {}


def test_untrusted_country_is_rejected(passport):
    sod, dgs = passport
    result = verify_passive_auth(sod, dgs, TrustStore([]))
    assert not result.valid
    assert any("trusted CSCA" in f for f in result.failures)


def test_data_group_not_in_sod_is_rejected(passport, trust):
    sod, dgs = passport
    result = verify_passive_auth(sod, {**dgs, 15: b"\x6f\x00"}, trust)
    assert not result.valid
    assert any("DG15" in f for f in result.failures)


def test_tampered_signature_is_rejected(passport, trust):
    sod, dgs = passport
    tampered = bytearray(sod)
    tampered[-5] ^= 0x01  # the signature value is the last field of the SOD
    result = verify_passive_auth(bytes(tampered), dgs, trust)
    assert not result.valid
    assert any("signature" in f for f in result.failures)


def test_expired_document_signer_is_rejected(passport, trust):
    sod, dgs = passport
    future = datetime(2099, 1, 1, tzinfo=UTC)
    result = verify_passive_auth(sod, dgs, trust, now=future)
    assert not result.valid
    assert any("validity period" in f for f in result.failures)


def test_garbage_is_reported_not_crashed(trust):
    result = verify_passive_auth(b"\x77\x03abc", {1: b"x"}, trust)
    assert not result.valid
    assert result.failures[0].startswith("malformed SOD")

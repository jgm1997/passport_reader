from types import SimpleNamespace

from app.config import production_problems


def secure(**overrides):
    values = {"require_crl": True, "master_lists_verified": True, "integrity": object()}
    return SimpleNamespace(**(values | overrides))


def test_a_secure_configuration_has_no_problems():
    assert production_problems(secure()) == []


def test_each_insecure_setting_is_reported():
    assert "REQUIRE_CRL" in production_problems(secure(require_crl=False))[0]
    assert "master lists" in production_problems(secure(master_lists_verified=False))[0]
    assert "INTEGRITY_MODE" in production_problems(secure(integrity=None))[0]

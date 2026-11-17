import copy

from app.integrity import (
    PACKAGE_NAME,
    IntegrityChecker,
    IntegrityMode,
    body_hash,
    evaluate,
)

NOW = 1_800_000_000_000
BODY = b'{"sod":"AAAA","dataGroups":{}}'

GENUINE = {
    "requestDetails": {
        "requestPackageName": PACKAGE_NAME,
        "requestHash": body_hash(BODY),
        "timestampMillis": str(NOW - 5_000),
    },
    "appIntegrity": {
        "appRecognitionVerdict": "UNRECOGNIZED_VERSION"
    },  # sideloaded dev build
    "deviceIntegrity": {"deviceRecognitionVerdict": ["MEETS_DEVICE_INTEGRITY"]},
}


def check(payload, **kwargs):
    return evaluate(payload, expected_hash=body_hash(BODY), now_ms=NOW, **kwargs)


def changed(path: list[str], value):
    payload = copy.deepcopy(GENUINE)
    target = payload
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = value
    return payload


def test_genuine_dev_build_passes():
    verdict = check(GENUINE)
    assert verdict.ok, verdict.problems
    assert "MEETS_DEVICE_INTEGRITY" in verdict.summary


def test_token_reused_on_another_body_fails():
    verdict = evaluate(
        GENUINE, expected_hash=body_hash(b'{"sod":"TAMPERED"}'), now_ms=NOW
    )
    assert "request hash mismatch" in verdict.problems


def test_other_app_fails():
    assert (
        "wrong package"
        in check(changed(["requestDetails", "requestPackageName"], "com.evil")).problems
    )


def test_old_token_fails():
    old = changed(["requestDetails", "timestampMillis"], str(NOW - 10 * 60 * 1000))
    assert "stale token" in check(old).problems


def test_compromised_device_fails():
    rooted = changed(["deviceIntegrity", "deviceRecognitionVerdict"], [])
    assert "device integrity not met" in check(rooted).problems


def test_release_policy_requires_a_play_build():
    assert not check(GENUINE, require_play_recognized=True).ok


def test_missing_or_garbage_tokens_never_crash():
    def broken_decoder(token):
        raise ValueError("not a token")

    checker = IntegrityChecker(IntegrityMode.REPORT, broken_decoder, clock=lambda: NOW)
    assert checker.check(None, BODY).problems == ("missing token",)
    assert not checker.check("garbage", BODY).ok


def test_checker_uses_the_received_bytes():
    checker = IntegrityChecker(
        IntegrityMode.ENFORCE, lambda token: GENUINE, clock=lambda: NOW
    )
    assert checker.check("token", BODY).ok
    assert not checker.check(
        "token", BODY + b" "
    ).ok  # one extra byte breaks the binding

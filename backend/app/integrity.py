"""Play Integrity: is this request coming from our app, on a genuine device?"""

from __future__ import annotations

import hashlib
import time
from collections.abc import Callable
from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PACKAGE_NAME = "es.jgm1997.passport_reader"
MAX_TOKEN_AGE_MS = 2 * 60 * 1000
CLOCK_SKEW_MS = 30 * 1000


class IntegrityMode(StrEnum):
    OFF = "off"  # not checked at all
    REPORT = "report"  # checked and logged, never blocks
    ENFORCE = "enforce"  # requests that fail are rejected


@dataclass(frozen=True)
class IntegrityVerdict:
    ok: bool
    problems: tuple[str, ...]
    summary: str = "-"  # verdict labels only (no personal data), for logs


def body_hash(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def evaluate(
    payload: dict[str, Any],
    *,
    expected_hash: str,
    now_ms: int,
    package: str = PACKAGE_NAME,
    require_play_recognized: bool = False,
) -> IntegrityVerdict:
    """Applies our policy to a decoded Play Integrity payload. Pure: easy to test/"""
    details = payload.get("requestDetails", {})
    device = payload.get("deviceIntegrity", {}).get("deviceRecognitionVerdict", [])
    app = payload.get("appIntegrity", {}).get("appRecognitionVerdict", "MISSING")

    problems = []
    if details.get("requestPackageName") != package:
        problems.append("wrong package")
    if details.get("requestHash") != expected_hash:
        problems.append("request hash mismatch")
    age = now_ms - int(details.get("timestampMillis", 0))
    if not -CLOCK_SKEW_MS <= age <= MAX_TOKEN_AGE_MS:
        problems.append("stale token")
    if "MEETS_DEVICE_INTEGRITY" not in device:
        problems.append("device integrity not met")
    if require_play_recognized and app != "PLAY_RECOGNIZED":
        problems.append("app not recognized by Play")

    summary = f"app={app} device={'+'.join(device) or 'NONE'}"
    return IntegrityVerdict(not problems, tuple(problems), summary)


Decoder = Callable[[str], dict[str, Any]]


class IntegrityChecker:
    def __init__(
        self,
        mode: IntegrityMode,
        decode: Decoder,
        *,
        require_play_recognized: bool = False,
        clock: Callable[[], int] = lambda: int(time.time() * 1000),
    ):
        self.mode = mode
        self._decode = decode
        self._require_play = require_play_recognized
        self._clock = clock

    def check(self, token: str | None, body: bytes) -> IntegrityVerdict:
        if not token:
            return IntegrityVerdict(False, ("missing token",))
        try:
            payload = self._decode(token)
        except Exception as e:  # noqa: BLE001 - any decode failure is a failed check, never a crash
            return IntegrityVerdict(
                False, (f"token not decodable ({type(e).__name__})",)
            )
        return evaluate(
            payload,
            expected_hash=body_hash(body),
            now_ms=self._clock(),
            require_play_recognized=self._require_play,
        )


class GooglePlayDecoder:
    """Asks Google's servers to decrypt and verify a token."""

    _SCOPE = "https://www.googleapis.com/auth/playintegrity"
    _URL = "https://playintegrity.googleapis.com/v1/{package}:decodeIntegrityToken"

    def __init__(self, service_account_file: str, package: str = PACKAGE_NAME):
        credentials = service_account.Credentials.from_service_account_file(
            service_account_file, scopes=[self._SCOPE]
        )
        self._session = AuthorizedSession(credentials)
        self._url = self._URL.format(package=package)

    def __call__(self, token: str) -> dict[str, Any]:
        response = self._session.post(
            self._url, json={"integrityToken": token}, timeout=10
        )
        response.raise_for_status()
        return response.json()["tokenPayloadExternal"]

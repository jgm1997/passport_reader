"""Reads the server's configuration from environment variables."""

import os
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from app.integrity import GooglePlayDecoder, IntegrityChecker, IntegrityMode
from app.revocation import CrlStore
from app.trust_store import TrustStore, load_certificates


@dataclass(frozen=True)
class Settings:
    trust: TrustStore
    crls: CrlStore
    integrity: IntegrityChecker
    require_crl: bool
    master_lists_verified: bool


def production_problems(settings: Settings) -> list[str]:
    """Settings that are acceptable in development but never in production."""
    problems = []
    if not settings.require_crl:
        problems.append("REQUIRE_CRL must be 1")
    if not settings.master_lists_verified:
        problems.append(
            "master lists must be verified against anchors/ (no ALLOW_UNVERIFIED_MASTER_LISTS)"
        )
    if settings.integrity is None:
        problems.append("INTEGRITY_MODE must be report or enforce")
    return problems


def load_settings(env: Mapping[str, str] = os.environ) -> Settings:
    anchors_dir = Path(env.get("ML_ANCHORS_DIR", "anchors"))
    anchors = load_certificates(anchors_dir) if anchors_dir.is_dir() else None
    trust = TrustStore.from_directory(
        env.get("TRUST_DIR", "trust"),
        ml_anchors=anchors,
        allow_unverified_master_lists=env.get("ALLOW_UNVERIFIED_MASTER_LISTS") == "1",
    )
    mode = IntegrityMode(os.environ.get("INTEGRITY_MODE", "off"))
    integrity = None
    if mode is not IntegrityMode.OFF:
        sa_file = os.environ.get("PLAY_INTEGRITY_SA_FILE")
        if not sa_file:
            raise ValueError(
                "INTEGRITY_MODE needs PLAY_INTEGRITY_SA_FILE (service account JSON)"
            )
        integrity = IntegrityChecker(
            mode,
            GooglePlayDecoder(sa_file),
            require_play_recognized=os.environ.get("REQUIRE_PLAY_RECOGNIZED") == "1",
        )
    settings = Settings(
        trust=trust,
        crls=CrlStore.from_directory(env.get("CRL_DIR", "crls")),
        integrity=integrity,
        require_crl=env.get("REQUIRE_CRL") == "1",
        master_lists_verified=anchors is not None,
    )
    if os.environ.get("APP_ENV") == "production":
        problems = production_problems(settings)
        if problems:
            raise ValueError(
                "Refusing to start in production:\n  -  " + "\n  -  ".join(problems)
            )
    return settings

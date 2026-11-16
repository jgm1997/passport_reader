"""Reads the server's configuration from environment variables."""

import os
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from backend.app.revocation import CrlStore
from backend.app.trust_store import TrustStore, load_certificates


@dataclass(frozen=True)
class Settings:
    trust: TrustStore
    crls: CrlStore
    require_crl: bool
    master_lists_verified: bool


def load_settings(env: Mapping[str, str] = os.environ) -> Settings:
    anchors_dir = Path(env.get("ML_ANCHORS_DIR", "anchors"))
    anchors = load_certificates(anchors_dir) if anchors_dir.is_dir() else None
    trust = TrustStore.from_directory(
        env.get("TRUST_DIR", "trust"),
        ml_anchors=anchors,
        allow_unverified_master_lists=env.get("ALLOW_UNVERIFIED_MASTER_LISTS") == "1",
    )
    return Settings(
        trust=trust,
        crls=CrlStore.from_directory(env.get("CRL_DIR", "crls")),
        require_crl=env.get("REQUIRE_CRL") == "1",
        master_lists_verified=anchors is not None,
    )

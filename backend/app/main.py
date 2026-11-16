"""Entry point: `uvicorn app.main:app`"""

import logging

from app.api import create_app
from app.config import load_settings

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("passport.verify")

settings = load_settings()
log.info(
    "Loaded %d CSCA certificates for %d countries; %d CRLs",
    len(settings.trust),
    len(settings.trust.countries),
    len(settings.crls),
)
if not settings.master_lists_verified:
    log.warning("Master list signatures are NOT verified (no anchors/ folder)")
if not settings.require_crl:
    log.warning("REQUIRE_CRL is off: missing or stale CRLs are only warnings")

app = create_app(settings.trust, settings.crls, require_crl=settings.require_crl)

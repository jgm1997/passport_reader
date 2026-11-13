"""Entry point: `uvicorn app.main:app`"""

import logging
import os

from app.api import create_app
from app.trust_store import TrustStore

logging.basicConfig(level=logging.INFO)

trust = TrustStore.from_directory(os.environ.get("TRUST_DIR", "trust"))
logging.getLogger("passport.verify").info(
    "Loaded %d CSCA certificates for %d countries", len(trust), len(trust.countries)
)

app = create_app(trust)

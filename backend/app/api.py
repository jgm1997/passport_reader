"""HTTP API for passport verification."""

from __future__ import annotations

import base64
import binascii
import logging
from typing import Annotated

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.passive_auth import verify_passive_auth
from app.trust_store import TrustStore

MAX_FILE_BYTES = 64 * 1024  # No SOD, DG1, DG15 or DG15 is anywhere near this size
MAX_B64_CHARS = 90_000  # 64 KiB encoded as base64, rounded up
FORBIDDEN_DGS = {3, 4}

Base64 = Annotated[str, StringConstraints(max_length=MAX_B64_CHARS)]
log = logging.getLogger("passport.verify")


class VerifyRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    sod: Base64
    data_groups: dict[int, Base64] = Field(
        alias="dataGroups", min_length=1, max_length=16
    )


class VerifyResponse(BaseModel):
    valid: bool
    issuingCountry: str | None
    hashAlgorithm: str | None
    authenticatedHashes: dict[int, str]  # hex
    verifiedDataGroups: list[int]
    failures: list[str]
    warnings: list[str]


def _decode(value: str, label: str) -> bytes:
    try:
        data = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(422, f"{label} is not valid base64")
    if not 0 < len(data) <= MAX_FILE_BYTES:
        raise HTTPException(422, f"{label} has an invaliod size")
    return data


def create_app(trust: TrustStore) -> FastAPI:
    app = FastAPI(title="Passport verification")

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok", "cscaCertificates": len(trust)}

    @app.post("/v1/passive-auth", response_model=VerifyResponse)
    def passive_auth(request: VerifyRequest) -> VerifyResponse:
        groups: dict[int, bytes] = {}
        for number, value in request.data_groups.items():
            if not 1 <= number <= 16:
                raise HTTPException(422, f"invalid data group number {number}")
            if number in FORBIDDEN_DGS:
                raise HTTPException(
                    422, "biometric data groups DG3/DG4 must never be sent"
                )
            groups[number] = _decode(value, f"DG{number}")

        result = verify_passive_auth(_decode(request.sod, "SOD"), groups, trust)

        # Log the outcome only: never names, numbers or raw data.
        log.info(
            "passive auth valid=%s country=%s failures=%d",
            result.valid,
            result.issuing_country,
            len(result.failures),
        )

        return VerifyResponse(
            valid=result.valid,
            issuingCountry=result.issuing_country,
            hashAlgorithm=result.hash_algorithm,
            authenticatedHashes={
                n: h.hex() for n, h in result.authenticated_hashes.items()
            },
            verifiedDataGroups=result.verified_data_groups,
            failures=result.failures,
            warnings=result.warnings,
        )

    return app

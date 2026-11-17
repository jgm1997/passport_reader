import base64

from app.api import create_app
from fastapi.testclient import TestClient


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


def test_verify_endpoint_accepts_a_genuine_passport(passport, trust):
    sod, dgs = passport
    client = TestClient(create_app(trust))
    response = client.post(
        "/v1/passive-auth",
        json={
            "sod": _b64(sod),
            "dataGroups": {str(n): _b64(v) for n, v in dgs.items()},
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["valid"] is True
    assert body["issuingCountry"] == "UT"


def test_invalid_base64_is_rejected(trust):
    client = TestClient(create_app(trust))
    response = client.post(
        "/v1/passive-auth", json={"sod": "not base64!", "dataGroups": {"1": "AA=="}}
    )
    assert response.status_code == 422


def test_biometric_data_groups_are_refused(passport, trust):
    sod, _ = passport
    client = TestClient(create_app(trust))
    response = client.post(
        "/v1/passive-auth", json={"sod": _b64(sod), "dataGroups": {"3": "AA=="}}
    )
    assert response.status_code == 422


def test_unknown_fields_are_rejected(passport, trust):
    sod, dgs = passport
    client = TestClient(create_app(trust))
    response = client.post(
        "/v1/passive-auth",
        json={
            "sod": _b64(sod),
            "dataGroups": {"1": _b64(dgs[1])},
            "debug": True,
        },
    )
    assert response.status_code == 422


def test_invalid_body_is_rejected(trust):
    client = TestClient(create_app(trust))
    response = client.post(
        "/v1/passive-auth", json={"dataGroups": {"1": "SECRET-MARKER"}}
    )
    assert "SECRET-MARKER" not in response.text

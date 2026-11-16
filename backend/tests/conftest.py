"""Builds a fake country ("Utopia") and a fake passport SOD with OpenSSL.

No real passport data is ever used in these tests.
"""

import hashlib
import subprocess

import pytest
from app.passive_auth import LdsSecurityObject
from app.trust_store import CscaMasterList, TrustStore
from asn1crypto import pem
from asn1crypto import x509 as asn1_x509


def _openssl(*args: str) -> None:
    subprocess.run(["openssl", *args], check=True, capture_output=True)


def _tlv(tag: int, content: bytes) -> bytes:
    """Wraps content in a DER tag-length-value header."""
    n = len(content)
    if n < 0x80:
        length = bytes([n])
    else:
        raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
        length = bytes([0x80 | len(raw)]) + raw
    return bytes([tag]) + length + content


@pytest.fixture(scope="session")
def utopia(tmp_path_factory):
    """A CSCA and a Document Signer for the fictional country UT."""
    d = tmp_path_factory.mktemp("utopia")
    _openssl(
        "req",
        "-x509",
        "-newkey",
        "rsa:2048",
        "-nodes",
        "-keyout",
        str(d / "csca.key"),
        "-out",
        str(d / "csca.pem"),
        "-days",
        "3650",
        "-subj",
        "/C=UT/O=Utopia/CN=CSCA Utopia",
        "-addext",
        "basicConstraints=critical,CA:TRUE",
        "-addext",
        "keyUsage=critical,keyCertSign,cRLSign",
    )
    _openssl(
        "req",
        "-newkey",
        "rsa:2048",
        "-nodes",
        "-keyout",
        str(d / "dsc.key"),
        "-out",
        str(d / "dsc.csr"),
        "-subj",
        "/C=UT/O=Utopia/CN=DS Utopia 1",
    )
    (d / "dsc.ext").write_text("keyUsage=critical,digitalSignature\n")
    _openssl(
        "x509",
        "-req",
        "-in",
        str(d / "dsc.csr"),
        "-CA",
        str(d / "csca.pem"),
        "-CAkey",
        str(d / "csca.key"),
        "-CAcreateserial",
        "-out",
        str(d / "dsc.pem"),
        "-days",
        "365",
        "-extfile",
        str(d / "dsc.ext"),
    )
    return d


@pytest.fixture(scope="session")
def passport(utopia):
    """(EF.SOD bytes, {dg number: dg bytes}) signed by Utopia's Document Signer."""
    dgs = {1: b"\x61\x10fake DG1 content", 2: b"\x75\x10fake DG2 photo..."}
    lds = LdsSecurityObject(
        {
            "version": 0,
            "hash_algorithm": {"algorithm": "sha256"},
            "data_group_hashes": [
                {"number": n, "hash": hashlib.sha256(b).digest()}
                for n, b in dgs.items()
            ],
        }
    )
    (utopia / "lds.der").write_bytes(lds.dump())
    _openssl(
        "cms",
        "-sign",
        "-binary",
        "-nodetach",
        "-econtent_type",
        "2.23.136.1.1.1",
        "-md",
        "sha256",
        "-signer",
        str(utopia / "dsc.pem"),
        "-inkey",
        str(utopia / "dsc.key"),
        "-in",
        str(utopia / "lds.der"),
        "-outform",
        "DER",
        "-out",
        str(utopia / "sod.der"),
    )
    sod = _tlv(
        0x77, (utopia / "sod.der").read_bytes()
    )  # EF.SOD's [APPLICATION 23] wrapper
    return sod, dgs


@pytest.fixture(scope="session")
def trust(utopia):
    trust_dir = utopia / "trust"
    trust_dir.mkdir(exist_ok=True)
    (trust_dir / "csca.pem").write_bytes((utopia / "csca.pem").read_bytes())
    return TrustStore.from_directory(trust_dir)


@pytest.fixture(scope="session")
def neverland(tmp_path_factory):
    """Another fictional country whose CSCA signs master lists (our 'anchor')."""
    d = tmp_path_factory.mktemp("neverland")
    _openssl(
        "req",
        "-x509",
        "-newkey",
        "rsa:2048",
        "-nodes",
        "-keyout",
        str(d / "anchor.key"),
        "-out",
        str(d / "anchor.pem"),
        "-days",
        "3650",
        "-subj",
        "/C=NL/O=Neverland/CN=CSCA Neverland",
        "-addext",
        "basicConstraints=critical,CA:TRUE",
        "-addext",
        "keyUsage=critical,keyCertSign,cRLSign",
    )
    _openssl(
        "req",
        "-newkey",
        "rsa:2048",
        "-nodes",
        "-keyout",
        str(d / "signer.key"),
        "-out",
        str(d / "signer.csr"),
        "-subj",
        "/C=NL/O=Neverland/CN=Master List Signer",
    )
    (d / "signer.ext").write_text("keyUsage=critical,digitalSignature\n")
    _openssl(
        "x509",
        "-req",
        "-in",
        str(d / "signer.csr"),
        "-CA",
        str(d / "anchor.pem"),
        "-CAkey",
        str(d / "anchor.key"),
        "-CAcreateserial",
        "-out",
        str(d / "signer.pem"),
        "-days",
        "365",
        "-extfile",
        str(d / "signer.ext"),
    )
    return d


@pytest.fixture(scope="session")
def master_list(utopia, neverland):
    """A master list, signed by Neverland, that vouches for Utopia's CSCA."""

    _, _, der = pem.unarmor((utopia / "csca.pem").read_bytes())
    content = CscaMasterList(
        {"version": 0, "cert_list": [asn1_x509.Certificate.load(der)]}
    )
    (neverland / "ml_content.der").write_bytes(content.dump())
    _openssl(
        "cms",
        "-sign",
        "-binary",
        "-nodetach",
        "-econtent_type",
        "2.23.136.1.1.2",
        "-md",
        "sha256",
        "-signer",
        str(neverland / "signer.pem"),
        "-inkey",
        str(neverland / "signer.key"),
        "-in",
        str(neverland / "ml_content.der"),
        "-outform",
        "DER",
        "-out",
        str(neverland / "list.ml"),
    )
    return (neverland / "list.ml").read_bytes()

"""Verifying CMS SignedData: the format of both passport SODs and CSCA master lsits."""

import hashlib
import hmac

from asn1crypto import cms, core
from asn1crypto import x509 as asn1_x509
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa

HASHES = {
    "sha1": hashes.SHA1,
    "sha224": hashes.SHA224,
    "sha256": hashes.SHA256,
    "sha384": hashes.SHA384,
    "sha512": hashes.SHA512,
}


class CmsError(Exception):
    """The CMS structure is malformed or uses something we don't support."""


def load_signed_data(data: bytes) -> cms.SignedData:
    info = cms.ContentInfo.load(data, strict=True)
    if info["content_type"].native != "signed_data":
        raise CmsError("not a CMS SignedData structure")
    return info["content"]


def encapsulated_content(signed_data: cms.SignedData, content_type: str) -> bytes:
    """Returns the signed bytes, after checking they are of the expected type."""
    encap = signed_data["encap_content_info"]
    if encap["content_type"].dotted != content_type:
        raise CmsError(f"unexpected content type {encap['content_type'].dotted}")
    content = encap["content"].native
    if not isinstance(content, bytes):
        raise CmsError("signed content is missing")
    return content


def signer_and_certificate(
    signed_data: cms.SignedData,
) -> tuple[cms.SignerInfo, x509.Certificate]:
    signers = signed_data["signer_infos"]
    if len(signers) != 1:
        return CmsError(f"expected exactly 1, found {len(signers)}")
    signer = signers[0]

    certificates = signed_data["certificates"]
    if isinstance(certificates, core.Void) or len(certificates) == 0:
        raise CmsError("no signer certificate included")

    sid = signer["sid"]
    for choice in certificates:
        cert = choice.chosen
        if not isinstance(cert, asn1_x509.Certificate):
            continue
        if sid.name == "issuer_and_serial_number":
            match = (
                cert.issuer == sid.chosen["issuer"]
                and cert.serial_number == sid.chosen["serial_number"].native
            )
        else:  # subject_key_identifier
            match = cert.key_identifier == sid.chosen.native
        if match:
            try:
                return signer, x509.load_der_x509_certificate(cert.dump())
            except ValueError as e:
                raise CmsError(
                    f"signer certificate can't be loaded (e.g. explicit EC parameters): {e}"
                ) from e
    raise CmsError("signer certificate not found")


def verify_signer(
    signer: cms.SignerInfo, content: bytes, content_type: str, cert: x509.Certificate
) -> None:
    """Raises InvalidSignature or CmsError unless `cert` really signed `content`."""
    _check_signed_attributes(signer, content, content_type)
    _verify_signature(cert.public_key(), signer)


def _check_signed_attributes(
    signer: cms.SignerInfo, content: bytes, content_type: str
) -> None:
    attrs = signer["signed_data"]
    if isinstance(attrs, core.Void) or len(attrs) == 0:
        raise CmsError("no signed attributes")

    found = {a["type"].native: a["values"] for a in attrs}
    if len(found) != len(attrs):
        raise CmsError("duplicate signed attributes")

    signed_type, digest = found.get("content_type"), found.get("message_digest")
    if not signed_type or not digest or len(signed_type) != 1 or len(digest) != 1:
        raise CmsError("content-type or message-digest attribute missing")
    if signed_type[0].dotted != content_type:
        raise CmsError("signed content-type attribute is wrong")

    digest_name = signer["digest_algorithm"]["algorithm"].native
    if digest_name not in HASHES:
        raise CmsError(f"unsupported digest algorithm: {digest_name}")
    actual = hashlib.new(digest_name, content).digest()
    if not hmac.compare_digest(digest[0].native, actual):
        raise CmsError("message digest does not match the signed content")


def _verify_signature(public_key, signer: cms.SignerInfo) -> None:
    # The signature covers the DER of the signed attributes re-tagged as a SET (0x31),
    # not the [0] IMPLICIT tag (0xA0) they carry inside SignerInfo (RFC 5652, 5.4).
    data = b"\x31" + signer["signed_attrs"].dump()[1:]
    signature = signer["signature"].native
    sig_algo = signer["signature_algorithm"]
    kind = sig_algo.signature_algo

    try:
        hash_name = sig_algo.hash_algo  # e.g. "sha256" for sha256_rsa / ecdsa / pss
    except (
        ValueError
    ):  # plain "rsaEncryption": the hash comes from the digest algorithm
        hash_name = signer["digest_algorithm"]["algorithm"].native
    if hash_name not in HASHES:
        raise CmsError(f"unsupported hash: {hash_name}")
    digest = HASHES[hash_name]()

    if kind == "rsassa_pkcs1v15" and isinstance(public_key, rsa.RSAPublicKey):
        public_key.verify(signature, data, padding.PKCS1v15(), digest)
    elif kind == "rsassa_pss" and isinstance(public_key, rsa.RSAPublicKey):
        params = sig_algo["parameters"]
        mgf_hash = params["mask_gen_algorithm"]["parameters"]["algorithm"].native
        if mgf_hash not in HASHES:
            raise CmsError(f"unsupported MGF1 hash: {mgf_hash}")
        public_key.verify(
            signature,
            data,
            padding.PSS(
                mgf=padding.MGF1(HASHES[mgf_hash]()),
                salt_length=params["salt_length"].native,
            ),
            digest,
        )
    elif kind == "ecdsa" and isinstance(public_key, ec.EllipticCurvePublicKey):
        public_key.verify(signature, data, ec.ECDSA(digest))
    else:
        raise CmsError(f"unsupported signature algorithm: {kind}")

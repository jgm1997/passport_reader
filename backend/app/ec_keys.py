"""
Loads public keys whose EC curve is written out as explicit parameters.

Many national PKIs (Germany's included) encode Brainpool curves with *explicit*
domain parameters instead of a curve name. The `cryptography` library only
accepts named curves, so we recognise the parameters ourselves and rebuild the
key on the matching named curve. Nothing is trusted on faith: p, a, b, the
generator's x coordinate and the order must ALL match a known curve exactly.
"""

from asn1crypto import keys
from asn1crypto import x509 as asn1_x509
from cryptography import x509
from cryptography.exceptions import UnsupportedAlgorithm
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa

# (p, a, b, generator x, order), taken from OpenSSL's built-in curve definitions
_KNOWN_CURVES: dict[str, tuple[int, int, int, int, int]] = {
    "brainpoolP256r1": (
        0xA9FB57DBA1EEA9BC3E660A909D838D726E3BF623D52620282013481D1F6E5377,
        0x7D5A0975FC2C3057EEF67530417AFFE7FB8055C126DC5C6CE94A4B44F330B5D9,
        0x26DC5C6CE94A4B44F330B5D9BBD77CBF958416295CF7E1CE6BCCDC18FF8C07B6,
        0x8BD2AEB9CB7E57CB2C4B482FFC81B7AFB9DE27E1E3BD23C23A4453BD9ACE3262,
        0xA9FB57DBA1EEA9BC3E660A909D838D718C397AA3B561A6F7901E0E82974856A7,
    ),
    "brainpoolP384r1": (
        0x8CB91E82A3386D280F5D6F7E50E641DF152F7109ED5456B412B1DA197FB71123ACD3A729901D1A71874700133107EC53,
        0x7BC382C63D8C150C3C72080ACE05AFA0C2BEA28E4FB22787139165EFBA91F90F8AA5814A503AD4EB04A8C7DD22CE2826,
        0x4A8C7DD22CE28268B39B55416F0447C2FB77DE107DCD2A62E880EA53EEB62D57CB4390295DBC9943AB78696FA504C11,
        0x1D1C64F068CF45FFA2A63A81B7C13F6B8847A3E77EF14FE3DB7FCAFE0CBD10E8E826E03436D646AAEF87B2E247D4AF1E,
        0x8CB91E82A3386D280F5D6F7E50E641DF152F7109ED5456B31F166E6CAC0425A7CF3AB6AF6B7FC3103B883202E9046565,
    ),
    "brainpoolP512r1": (
        0xAADD9DB8DBE9C48B3FD4E6AE33C9FC07CB308DB3B3C9D20ED6639CCA703308717D4D9B009BC66842AECDA12AE6A380E62881FF2F2D82C68528AA6056583A48F3,
        0x7830A3318B603B89E2327145AC234CC594CBDD8D3DF91610A83441CAEA9863BC2DED5D5AA8253AA10A2EF1C98B9AC8B57F1117A72BF2C7B9E7C1AC4D77FC94CA,
        0x3DF91610A83441CAEA9863BC2DED5D5AA8253AA10A2EF1C98B9AC8B57F1117A72BF2C7B9E7C1AC4D77FC94CADC083E67984050B75EBAE5DD2809BD638016F723,
        0x81AEE4BDD82ED9645A21322E9C4C6A9385ED9F70B5D916C1B43B62EEF4D0098EFF3B1F78E2D0D48D50D1687B93B97D5F7C6D5047406A5E688B352209BCB9F822,
        0xAADD9DB8DBE9C48B3FD4E6AE33C9FC07CB308DB3B3C9D20ED6639CCA70330870553E5C414CA92619418661197FAC10471DB1D381085DDADDB58796829CA90069,
    ),
}

_CURVE_CLASSES = {
    "brainpoolP256r1": ec.BrainpoolP256R1,
    "brainpoolP384r1": ec.BrainpoolP384R1,
    "brainpoolP512r1": ec.BrainpoolP512R1,
}


def match_explicit_curve(spki_der: bytes) -> tuple[str, bytes]:
    """
    Returns (curve name, encoded public point) for an EC key with explicit params.

    Raises ValueError if the key isn't EC with explicit parameters, or if the
    parameters don't exactly match a curve we know.
    """
    spki = keys.PublicKeyInfo.load(spki_der)
    algorithm = spki["algorithm"]
    if algorithm["algorithm"].native != "ec":
        raise ValueError("not an elliptic-curve key")
    params = algorithm["parameters"]
    if params.name != "specified":
        raise ValueError("curve is not given as explicit parameters")

    spec = params.chosen
    if spec["field_id"]["field_type"].native != "prime_field":
        raise ValueError("only prime-field curves are supported")
    p = spec["field_id"]["parameters"].native
    a = int.from_bytes(spec["curve"]["a"].native, "big")
    b = int.from_bytes(spec["curve"]["b"].native, "big")
    n = spec["order"].native
    base = spec["base"].native
    size = (p.bit_length() + 7) // 8
    if len(base) < 1 + size or base[0] not in (2, 3, 4):
        raise ValueError("malformed generator point")
    gx = int.from_bytes(base[1 : 1 + size], "big")

    for name, known in _KNOWN_CURVES.items():
        if (p, a, b, gx, n) == known:
            return name, spki["public_key"].native
    raise ValueError("explicit curve parameters don't match any supported curve")


def public_key_of(cert: x509.Certificate):
    """Like cert.public_key(), but also accepts known curves with explicit parameters."""
    try:
        return cert.public_key()
    except UnsupportedAlgorithm:
        der = cert.public_bytes(serialization.Encoding.DER)
        spki_der = asn1_x509.Certificate.load(der)["tbs_certificate"][
            "subject_public_key_info"
        ].dump()
        name, point = match_explicit_curve(spki_der)
        return ec.EllipticCurvePublicKey.from_encoded_point(
            _CURVE_CLASSES[name](), point
        )


def verify_certificate_signature(cert: x509.Certificate, issuer_key) -> None:
    """
    Raises InvalidSignature unless `issuer_key` signed `cert`.

    Same check as cert.verify_directly_issued_by(), but it takes the key itself,
    so it also works with keys loaded by public_key_of().
    """
    algorithm = (
        cert.signature_algorithm_parameters
    )  # PKCS1v15 / PSS padding, or ECDSA(hash)
    if isinstance(issuer_key, rsa.RSAPublicKey):
        issuer_key.verify(
            cert.signature,
            cert.tbs_certificate_bytes,
            algorithm,
            cert.signature_hash_algorithm,
        )
    elif isinstance(issuer_key, ec.EllipticCurvePublicKey):
        issuer_key.verify(cert.signature, cert.tbs_certificate_bytes, algorithm)
    else:
        raise TypeError(f"unsupported issuer key type: {type(issuer_key).__name__}")

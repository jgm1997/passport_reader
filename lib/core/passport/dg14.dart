import 'dart:typed_data';

import 'package:passport_reader/core/asn1/der.dart';

enum ChipAuthCipher { tripleDes, aes128, aes192, aes256 }

/// How the chip's elliptic curve is describerd in DG14.
sealed class CurveSpec {
  const CurveSpec();
}

class NamedCurve extends CurveSpec {
  final String oid;
  const NamedCurve(this.oid);
}

class ExplicitCurve extends CurveSpec {
  final BigInt a;
  final BigInt b;
  final BigInt generatorX;
  final BigInt order;

  const ExplicitCurve({
    required this.a,
    required this.b,
    required this.generatorX,
    required this.order,
  });
}

class Dg14Exception implements Exception {
  final String message;
  const Dg14Exception(this.message);

  @override
  String toString() => 'Dg14Excpetion: $message';
}

/// Everything needed to run Chip Authentication against the chip
class ChipAuthSetup {
  final String protocolOid;
  final Uint8List protocolOidBytes; // raw OID value, sent in MSE:Set AT (AES)
  final ChipAuthCipher cipher;
  final CurveSpec curve;
  final Uint8List publicPoint; // chip's static public key (uncompressed point)
  final int? keyId;

  const ChipAuthSetup({
    required this.protocolOid,
    required this.protocolOidBytes,
    required this.cipher,
    required this.curve,
    required this.publicPoint,
    this.keyId,
  });

  String get description =>
      '${cipher.name}, ${switch (curve) {
        NamedCurve(:final oid) => 'curve $oid',
        ExplicitCurve() => 'explicit curve',
      }}';
}

const _idPkEcdh = '0.4.0.127.0.7.2.2.1.2';
const _idPkDh = '0.4.0.127.0.7.2.2.1.1';
const _caDhPrefix = '0.4.0.127.0.7.2.2.3.1';
const _idEcPublicKey = '1.2.840.10045.2.1.';
const _primeField = '1.2.840.10045.1.1';

const _caCiphers = {
  '0.4.0.127.0.7.2.2.3.2.1': ChipAuthCipher.tripleDes,
  '0.4.0.127.0.7.2.2.3.2.2': ChipAuthCipher.aes128,
  '0.4.0.127.0.7.2.2.3.2.3': ChipAuthCipher.aes192,
  '0.4.0.127.0.7.2.2.3.2.4': ChipAuthCipher.aes256,
};

// id-CA-ECDH-3DES-CBC-CBC: the default when DG14 has no ChipAuthenticationInfo.
const _defaultCaOid = '0.4.0.127.0.7.2.2.3.2.1';
final _defaultCaOidBytes = Uint8List.fromList([
  0x04,
  0x00,
  0x7F,
  0x00,
  0x07,
  0x02,
  0x02,
  0x03,
  0x02,
  0x01,
]);
typedef _ChipKey = ({CurveSpec curve, Uint8List point, int? keyId});

/// Reads DG14 (the raw file bytes, tag 0x6E) into a [ChipAuthSetup].
/// Throws [Dg14Exception] if the file is malformed or uses something unsupported.
ChipAuthSetup parseDg14(Uint8List dg14) {
  try {
    return _parse(dg14);
  } on FormatException catch (e) {
    throw Dg14Exception('DG14 could not be parsed: ${e.message}');
  } on RangeError {
    throw const Dg14Exception('DG14 could not be parsed');
  }
}

ChipAuthSetup _parse(Uint8List dg14) {
  final file = Der.parse(dg14);
  if (file.tag != 0x6E) throw const FormatException('Not a DG14 file');
  final securityInfos = Der.parse(file.value);
  if (securityInfos.tag != 0x31) {
    throw const FormatException('SecurityInfos SET expected');
  }

  ({String oid, Uint8List oidBytes, int? keyId})? caInfo;
  final keys = <_ChipKey>[];

  for (final info in securityInfos.children) {
    if (info.tag != 0x30) continue;
    final fields = info.children;
    if (fields.length < 2 || fields[0].tag != 0x06) continue;
    final protocol = fields[0].oid;
    final keyId = fields.length > 2 ? fields[2].smallInt : null;

    if (_caCiphers.containsKey(protocol)) {
      if (fields[1].smallInt != 1) {
        throw const Dg14Exception(
          'Only Chip Authentication version 1 is supported',
        );
      }
      caInfo = (oid: protocol, oidBytes: fields[0].value, keyId: keyId);
    } else if (protocol == _idPkEcdh) {
      final (:curve, :point) = _parsePublicKey(fields[1]);
      keys.add((curve: curve, point: point, keyId: keyId));
    } else if (protocol == _idPkDh || protocol.startsWith(_caDhPrefix)) {
      throw const Dg14Exception(
        'Chip Authentication with classic Diffie-Hellman is not supported.',
      );
    }
    // Other SecurityInfos (Terminal Authentication, PACE, ...) are ignored.
  }

  if (keys.isEmpty) {
    throw const Dg14Exception('DG14 has no ECDHG chip public key');
  }
  final wantedKeyId = caInfo?.keyId;
  if (wantedKeyId == null && keys.length > 1) {
    throw const Dg14Exception('Several chip keys but no key id to choose one');
  }
  final key = wantedKeyId == null
      ? keys.first
      : keys.firstWhere(
          (k) => k.keyId == wantedKeyId,
          orElse: () =>
              throw const Dg14Exception('No chip key matches the key id'),
        );
  return ChipAuthSetup(
    protocolOid: caInfo?.oid ?? _defaultCaOid,
    protocolOidBytes: caInfo?.oidBytes ?? _defaultCaOidBytes,
    cipher: caInfo == null ? ChipAuthCipher.tripleDes : _caCiphers[caInfo.oid]!,
    curve: key.curve,
    publicPoint: key.point,
    keyId: key.keyId,
  );
}

({CurveSpec curve, Uint8List point}) _parsePublicKey(Der spki) {
  final parts = spki.children;
  if (spki.tag != 0x30 ||
      parts.length != 2 ||
      parts[0].tag != 0x30 ||
      parts[1].tag != 0x03) {
    throw const FormatException('Malformed SubjectPublicKeyInfo');
  }
  final algorithm = parts[0].children;
  if (algorithm.length != 2 || algorithm[0].oid != _idEcPublicKey) {
    throw const Dg14Exception('The chip key is not an elliptic curve');
  }
  final bits = parts[1].value;
  if (bits.isEmpty || bits[0] != 0) {
    throw const FormatException('Malformed key bits');
  }
  final point = Uint8List.sublistView(bits, 1);
  if (point.isEmpty || point[0] != 0x04) {
    throw const Dg14Exception(
      'Only uncompressed chip public keys are supported',
    );
  }
  return (curve: _parseCurve(algorithm[1]), point: point);
}

CurveSpec _parseCurve(Der params) {
  if (params.tag == 0x06) return NamedCurve(params.oid);
  if (params.tag != 0x30) {
    throw const FormatException('Unknown curve parameters');
  }

  // ECParameters: version, fieldID, curve(a, b, [seed]), base, order, [cofactor]
  final p = params.children;
  if (p.length < 5) throw const FormatException('Incomplete explicit curve');
  final field = p[1].children;
  if (field.isEmpty || field[0].oid != _primeField) {
    throw const Dg14Exception('Only prime-field curves are supported');
  }
  final coefficients = p[2].children;
  if (coefficients.length < 2) {
    throw const FormatException('Missing curve coedfficients');
  }
  final base = p[3].value;
  if (base.isEmpty || base[0] != 0x04 || base.length.isEven) {
    throw const FormatException('Malformed curve generator');
  }
  final size = (base.length - 1) ~/ 2;
  return ExplicitCurve(
    a: coefficients[0].unsigned,
    b: coefficients[1].unsigned,
    generatorX: bytesToUnsigned(Uint8List.sublistView(base, 1, 1 + size)),
    order: p[4].unsigned,
  );
}

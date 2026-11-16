import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:passport_reader/core/utils/bytes.dart';
import 'package:passport_reader/core/verification/verification_result.dart';

/// true only if the server verified the SOD AND the photo's bytes hash to the
/// DG2 value the issuing country signed.
bool photoMatchesSignedHash(Uint8List rawDg2, VerificationResult result) {
  final expected = result.authenticatedHashes[2];
  final algorithm = _hashAlgorithm(result.hashAlgorithm);
  if (!result.valid || expected == null || algorithm == null) return false;
  return constantTimeEquals(algorithm.convert(rawDg2).bytes, expected);
}

Hash? _hashAlgorithm(String? name) => switch (name) {
  'sha1' => sha1,
  'sha224' => sha224,
  'sha256' => sha256,
  'sha384' => sha384,
  'sha512' => sha512,
  _ => null,
};

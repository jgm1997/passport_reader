import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/verification/photo_integrity.dart';
import 'package:passport_reader/core/verification/verification_result.dart';

final _photo = Uint8List.fromList(utf8.encode('fake DG2 bytes'));

VerificationResult _result({
  bool valid = true,
  String algorithm = 'sha256',
  List<int>? dg2Hash,
}) => VerificationResult(
  valid: valid,
  issuingCountry: 'UT',
  hashAlgorithm: algorithm,
  authenticatedHashes: {if (dg2Hash != null) 2: Uint8List.fromList(dg2Hash)},
  verifiedDataGroups: const [1],
  failures: const [],
  warnings: const [],
);

void main() {
  test('genuine photo matches the signed hash', () {
    final result = _result(dg2Hash: sha256.convert(_photo).bytes);
    expect(photoMatchesSignedHash(_photo, result), isTrue);
  });

  test('works with other hash algorithms too', () {
    final result = _result(
      algorithm: 'sha1',
      dg2Hash: sha1.convert(_photo).bytes,
    );
    expect(photoMatchesSignedHash(_photo, result), isTrue);
  });

  test('an altered photo does not match', () {
    final result = _result(dg2Hash: sha256.convert(_photo).bytes);
    final altered = Uint8List.fromList([..._photo, 0]);
    expect(photoMatchesSignedHash(altered, result), isFalse);
  });

  test('never claims authenticity when the server said invalid', () {
    final result = _result(valid: false, dg2Hash: sha256.convert(_photo).bytes);
    expect(photoMatchesSignedHash(_photo, result), isFalse);
  });

  test('unknown algorithms and missing hashes are not a match', () {
    expect(
      photoMatchesSignedHash(_photo, _result(algorithm: 'md5', dg2Hash: [1])),
      isFalse,
    );
    expect(photoMatchesSignedHash(_photo, _result()), isFalse);
  });
}

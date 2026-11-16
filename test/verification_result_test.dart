import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/verification/verification_result.dart';

Map<String, dynamic> _json({Map<String, dynamic> override = const {}}) =>
    jsonDecode(
      jsonEncode({
        'valid': true,
        'issuingCountry': 'UT',
        'hashAlgorithm': 'sha256',
        'authenticatedHashes': {'1': 'aa', '2': 'bb'},
        'verifiedDataGroups': [1],
        'failures': [],
        'warnings': ['no trusted CRL available for UT'],
        ...override,
      }),
    ) as Map<String, dynamic>;

void main() {
  test('parses a valid response', () {
    final result = VerificationResult.fromJson(_json());
    expect(result.valid, isTrue);
    expect(result.issuingCountry, 'UT');
    expect(result.authenticatedHashes[2], [0xbb]);
    expect(result.warnings, hasLength(1));
  });

  test('accepts null country when verification failed early', () {
    final result = VerificationResult.fromJson(
      _json(override: {'valid': false, 'issuingCountry': null}),
    );
    expect(result.issuingCountry, isNull);
  });

  test('rejects missing fields and wrong types', () {
    final missing = _json()..remove('failures');
    expect(() => VerificationResult.fromJson(missing), throwsFormatException);
    expect(
      () => VerificationResult.fromJson(_json(override: {'valid': 'yes'})),
      throwsFormatException,
    );
    expect(
      () => VerificationResult.fromJson(
        _json(
          override: {
            'failures': [1],
          },
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => VerificationResult.fromJson(
        _json(
          override: {
            'authenticatedHashes': {'99': 'aa'},
          },
        ),
      ),
      throwsFormatException,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/mrz/mrz_validators.dart';

void main() {
  group('validateDocumentNumber', () {
    test('accepts a valid number', () {
      expect(validateDocumentNumber('L898902C3'), isNull);
    });

    test('accepts lowercase and spaces', () {
      expect(validateDocumentNumber(' l898 902c3'), isNull);
    });

    test('rejects empty input', () {
      expect(validateDocumentNumber(''), isNotNull);
    });

    test('rejects symbols', () {
      expect(validateDocumentNumber('L898~902'), isNotNull);
    });

    test('rejects more than 9 characters', () {
      expect(validateDocumentNumber('L898902C30'), isNotNull);
    });
  });

  group('date validators', () {
    final today = DateTime.utc(2026, 11, 10);
    final birth = DateTime.utc(1997, 12, 4);

    test('rejects a future date of birth', () {
      expect(
        validateDateOfBirth(DateTime.utc(2030, 1, 1), today: today),
        isNotNull,
      );
    });
    test('rejects expiry before birth', () {
      expect(
        validateDateOfExpiry(DateTime.utc(1970, 1, 1), dateOfBirth: birth),
        isNotNull,
      );
    });
    test('accepts a normal pair', () {
      expect(validateDateOfBirth(birth, today: today), isNull);
      expect(
        validateDateOfExpiry(DateTime.utc(2030, 1, 1), dateOfBirth: birth),
        isNull,
      );
    });
  });
}

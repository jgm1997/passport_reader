import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/mrz/check_digit.dart';
import 'package:passport_reader/core/mrz/mrz_parser.dart';

void main() {
  // Official ICAO 9303 specimen passport.
  const line1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<';
  const line2 = 'L898902C36UTO7408122F1204159ZE184226B<<<<<10';
  final fixedToday = DateTime(2026, 11, 10);

  group('computeCheckDigit', () {
    test('matches the ICAO specimen document number', () {
      expect(computeCheckDigit('L898902C3'), 6);
    });

    test('treats filler characters as zero', () {
      expect(computeCheckDigit('<<<<<<<<<'), 0);
    });
  });

  group('MrzParser.parseTd3', () {
    test('parses the ICAO specimen', () {
      final mrz = MrzParser.parseTd3(line1, line2, now: fixedToday);

      expect(mrz.documentType, 'P');
      expect(mrz.issuingState, 'UTO');
      expect(mrz.surname, 'ERIKSSON');
      expect(mrz.givenNames, 'ANNA MARIA');
      expect(mrz.documentNumber, 'L898902C3');
      expect(mrz.nationality, 'UTO');
      expect(mrz.dateOfBirth, DateTime.utc(1974, 8, 12));
      expect(mrz.sex, 'F');
      expect(mrz.dateOfExpiry, DateTime.utc(2012, 4, 15));
      expect(mrz.optionalData, 'ZE184226B');
      expect(mrz.isExpired(fixedToday), isTrue);
    });

    test('accepts lowercase and stray spaces', () {
      final mrz = MrzParser.parseTd3(
        ' ${line1.toLowerCase()} ',
        line2.replaceFirst('L898', 'L 898'),
        now: fixedToday,
      );
      expect(mrz.documentNumber, 'L898902C3');
    });

    test('rejects a tampered document number', () {
      final tampered = line2.replaceFirst('L898902C3', 'L898902C4');
      expect(
        () => MrzParser.parseTd3(line1, tampered, now: fixedToday),
        throwsA(isA<MrzParseException>()),
      );
    });

    test('rejects lines of the wrong length', () {
      expect(
        () => MrzParser.parseTd3(line1, line2.substring(0, 40)),
        throwsA(isA<MrzParseException>()),
      );
    });

    test('rejects invalid characters', () {
      final garbage = line2.replaceFirst('L898', 'L8#8');
      expect(
        () => MrzParser.parseTd3(line1, garbage),
        throwsA(isA<MrzParseException>()),
      );
    });

    test('sex "<"is parsed as "X" (position 20 has no check digit)', () {
      // Strings are immutable; replaceRange returns a new string.
      final nbLine2 = line2.replaceRange(20, 21, '<');
      final mrz = MrzParser.parseTd3(line1, nbLine2, now: fixedToday);
      expect(mrz.sex, 'X');
    });
  });
}

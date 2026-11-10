import 'package:passport_reader/core/mrz/check_digit.dart';
import 'package:passport_reader/core/mrz/mrz_data.dart';

/// Thrown when an MRZ cannot be parsed or fails validation
class MrzParseException implements Exception {
  final String message;

  MrzParseException(this.message);

  @override
  String toString() => 'MrzParserException: $message';
}

/// Parses TD3 (passport) MRZs: two lines of 44 characters each.
class MrzParser {
  static const int _lineLength = 44;

  static MrzData parseTd3(String line1, String line2, {DateTime? now}) {
    final l1 = _normalize(line1);
    final l2 = _normalize(line2);

    if (l1.length != _lineLength || l2.length != _lineLength) {
      throw MrzParseException(
        'Each line must be $_lineLength characters '
        '(got ${l1.length} and ${l2.length})',
      );
    }
    if (!l1.startsWith('P')) {
      throw MrzParseException('Not a passport MRZ (must start with "P").');
    }

    // --- Validate every check digit before trusting any value ---
    final documentNumberField = l2.substring(0, 9);
    final birthField = l2.substring(13, 19);
    final expiryField = l2.substring(21, 27);
    final optionalField = l2.substring(28, 42);
    final compositeField =
        l2.substring(0, 10) + l2.substring(13, 20) + l2.substring(21, 43);

    _verify('document number', documentNumberField, l2[9]);
    _verify('date of birth', birthField, l2[19]);
    _verify('date of expiry', expiryField, l2[27]);
    _verify('optional data', optionalField, l2[43]);
    _verify('document number', compositeField, l2[43]);

    // --- Extract the fields ---
    final today = now ?? DateTime.now();
    final (surname, givenNames) = _parseNames(l1.substring(5));

    return MrzData(
      documentType: l1.substring(0, 2).replaceAll('<', ''),
      issuingState: l1.substring(2, 5).replaceAll('<', ''),
      surname: surname,
      givenNames: givenNames,
      documentNumber: documentNumberField.replaceAll('<', ''),
      nationality: l2.substring(10, 13).replaceAll('<', ''),
      dateOfBirth: _parseDate(birthField, isBirthDate: true, today: today),
      sex: l2[20] == '<' ? 'X' : l2[20],
      dateOfExpiry: _parseDate(expiryField, isBirthDate: false, today: today),
      optionalData: optionalField.replaceAll('<', ''),
    );
  }

  /// IUppercases and removes spaces that OCR or users may introduce
  static String _normalize(String line) =>
      line.trim().toUpperCase().replaceAll(' ', '');

  static void _verify(String name, String field, String checkChar) {
    if (!isCheckDigitValid(field, checkChar)) {
      throw MrzParseException('Check digit failed for $name');
    }
  }

  /// Splits "SURNAME<<GIVENNAMES<<<<<" into ("SURNAME", "GIVEN NAMES")
  static (String, String) _parseNames(String field) {
    final separator = field.indexOf('<<');
    if (separator == -1) return (_cleanName(field), '');

    return (
      _cleanName(field.substring(0, separator)),
      _cleanName(field.substring(separator + 2)),
    );
  }

  static String _cleanName(String raw) =>
      raw.replaceAll('<', '').trim().replaceAll(RegExp(r'\s+'), '');

  /// Converts YYMMDD into a UTC date, resolving the missing century
  static DateTime _parseDate(
    String yymmdd, {
    required bool isBirthDate,
    required DateTime today,
  }) {
    final yy = int.tryParse(yymmdd.substring(0, 2));
    final mm = int.tryParse(yymmdd.substring(2, 4));
    final dd = int.tryParse(yymmdd.substring(4, 6));
    if (yy == null || mm == null || dd == null) {
      throw MrzParseException('Invalida date: "$yymmdd"');
    }

    var year = 2000 + yy;
    // A birth date can't be in the future, so "74" must mean 1974
    if (isBirthDate && year > today.year) year -= 100;

    final date = DateTime.utc(year, mm, dd);
    // DateTime silently rolls 31 Feb into 3 Mar, so we check it didn't
    if (date.month != mm || date.day != dd) {
      throw MrzParseException('Invalid date: "$yymmdd"');
    }

    return date;
  }
}

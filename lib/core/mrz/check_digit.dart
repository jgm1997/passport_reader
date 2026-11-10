/// Computes the ICAO 9303 check digit for an MRZ field.
///
/// Each character is converted to a number, multiplied by a repeating weight
/// of 7, 3, 1, summed, and the result is taken modulo 10.
int computeCheckDigit(String input) {
  const weights = [7, 3, 1];
  var sum = 0;

  for (var i = 0; i < input.length; i++) {
    sum += _charValue(input[i]) * weights[i % 3];
  }
  return sum % 10;
}

/// Return true when [field] produces the check digit written in [checkChar].
bool isCheckDigitValid(String field, String checkChar) {
  // Some passports use '<' as the check digit for an empty optional field
  final expected = checkChar == '<' ? 0 : int.tryParse(checkChar);
  if (expected == null) return false;
  return computeCheckDigit(field) == expected;
}

/// Converts a single MRZ character into its numeric value
int _charValue(String char) {
  if (char == '<') return 0;

  final code = char.codeUnitAt(0);
  if (code >= 0x30 && code <= 0x39) return code - 0x30; // '0'..'9' -> 0..9
  if (code >= 0x41 && code <= 0x5A) return code - 0x41; // 'A'..'Z' --> A..Z

  throw FormatException('Invalid MRZ character: "$char"');
}

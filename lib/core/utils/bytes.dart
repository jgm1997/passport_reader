import 'dart:typed_data';

final RegExp _hexPattern = RegExp(r'^[0-9a-fA-F]*$');

/// Decodes a hex string ("0aff") into bytes. Rejects anything that isn't hex.
Uint8List hexToBytes(String hex) {
  if (hex.length.isOdd || !_hexPattern.hasMatch(hex)) {
    throw const FormatException('Invalid hex string');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Compares two byte lists in constant time (no early exit on the first difference)
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

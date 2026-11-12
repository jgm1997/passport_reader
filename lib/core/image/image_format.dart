import 'dart:typed_data';

enum DetectedImageFormat { jpeg, jpeg2000, unknown }

/// Identifies an image by its first bytes ("magic numbers"),
/// instead of trusting a format label stored next to it.
DetectedImageFormat detectImageFormat(Uint8List bytes) {
  if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) {
    return DetectedImageFormat.jpeg;
  }

  // JP2 file: a 12 byte signature box whose type is "jP  ".
  if (_startsWith(bytes, const [
    0x00,
    0x00,
    0x00,
    0x0C,
    0x6A,
    0x50,
    0x20,
    0x20,
  ])) {
    return DetectedImageFormat.jpeg2000;
  }

  // Raw JPEG2000 codestream: SOC marker (FF4F) followed by SIZ (FF51).
  if (_startsWith(bytes, const [0xFF, 0x4F, 0xFF, 0x51])) {
    return DetectedImageFormat.jpeg2000;
  }
  return DetectedImageFormat.unknown;
}

bool _startsWith(Uint8List bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

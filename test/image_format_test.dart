import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/image/image_format.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  test('detects JPEG', () {
    expect(
      detectImageFormat(_bytes([0xFF, 0xD8, 0xFF, 0xE0])),
      DetectedImageFormat.jpeg,
    );
  });

  test('detects a JP2 file', () {
    expect(
      detectImageFormat(_bytes([0, 0, 0, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D])),
      DetectedImageFormat.jpeg2000,
    );
  });

  test('detects a raw JPEG2000 codestream', () {
    expect(
      detectImageFormat(_bytes([0xFF, 0x4F, 0xFF, 0x51, 0x00])),
      DetectedImageFormat.jpeg2000,
    );
  });

  test('short or unknown input is unknown, not a crash', () {
    expect(detectImageFormat(_bytes([0xFF])), DetectedImageFormat.unknown);
    expect(
      detectImageFormat(_bytes([1, 2, 3, 4])),
      DetectedImageFormat.unknown,
    );
  });
}

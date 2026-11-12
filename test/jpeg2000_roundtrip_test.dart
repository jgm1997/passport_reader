import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:j2k/j2k.dart';
import 'package:passport_reader/core/image/face_image_decoder.dart';
import 'package:passport_reader/core/image/image_format.dart';

/// Builds a binary PGM (P5, grey) or PPM (P6, RGB) file in memory.
Uint8List _pnm(String magic, int width, int height, List<int> samples) =>
    Uint8List.fromList([
      ...'$magic\n$width $height\n255\n'.codeUnits,
      ...samples,
    ]);

void main() {
  const width = 4;
  const height = 4;

  // A grey gradient: 0, 16, 32 … 240. Every pixel is different,
  // so a decoder that scrambles pixel order would be caught.
  final grey = List<int>.generate(width * height, (i) => i * 16);
  final greyAsRgba = [
    for (final g in grey) ...[g, g, g, 255],
  ];

  group('JPEG2000 round trip (synthetic images, no passport data)', () {
    test('grey raw codestream decodes to identical pixels', () {
      final encoded = encodeJpeg2000(_pnm('P5', width, height, grey));

      expect(detectImageFormat(encoded), DetectedImageFormat.jpeg2000);

      final result = jpeg2000ToRgba(encoded);
      expect(result.width, width);
      expect(result.height, height);
      expect(result.rgba, greyAsRgba);
    });

    test('grey JP2 file (the box format passports often use)', () {
      final encoded = encodeJpeg2000(
        _pnm('P5', width, height, grey),
        options: const Jpeg2000EncodeOptions(wrapInJp2: true),
      );

      // Bytes 4–7 of a JP2 file spell "jP  ": our magic-number check.
      expect(encoded.sublist(4, 8), 'jP  '.codeUnits);
      expect(detectImageFormat(encoded), DetectedImageFormat.jpeg2000);
      expect(jpeg2000ToRgba(encoded).rgba, greyAsRgba);
    });

    test('RGB colour image survives the trip', () {
      final rgb = List<int>.generate(width * height * 3, (i) => (i * 7) % 256);
      final expected = [
        for (var p = 0; p < width * height; p++) ...[
          rgb[p * 3],
          rgb[p * 3 + 1],
          rgb[p * 3 + 2],
          255,
        ],
      ];

      final encoded = encodeJpeg2000(_pnm('P6', width, height, rgb));
      expect(jpeg2000ToRgba(encoded).rgba, expected);
    });
  });

  group('hostile input', () {
    test('truncated garbage becomes a FaceImageException', () {
      // Starts like a real codestream, then stops: a classic parser trap.
      final garbage = Uint8List.fromList([0xFF, 0x4F, 0xFF, 0x51, 1, 2, 3]);
      expect(() => jpeg2000ToRgba(garbage), throwsA(isA<FaceImageException>()));
    });

    test('oversized images are refused by the size budget', () {
      // 3000 px wide: larger than our 2000 px limit.
      final wide = encodeJpeg2000(_pnm('P5', 3000, 1, List.filled(3000, 128)));
      expect(() => jpeg2000ToRgba(wide), throwsA(isA<FaceImageException>()));
    });
  });
}

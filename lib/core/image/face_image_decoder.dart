import 'dart:typed_data';

import 'package:j2k/j2k.dart';

/// A decoded image as raw RGBA pixels: 4 bytes per pixel, row by row.
typedef RgbaImage = ({int width, int height, Uint8List rgba});

class FaceImageException implements Exception {
  final String reason;
  const FaceImageException(this.reason);

  @override
  String toString() => 'FaceImageException: $reason';
}

// Passport photos are small (typically under 1000px a side).
// Anything bigger is suspicious, so refuse it before decoding.
const int _maxDimension = 2000;
const int _maxPixels = 4 * 1000 * 1000;

/// Decodes JPEG2000 bytes into RGBA. Pure Dart, safe to run in an isolate.
RgbaImage jpeg2000ToRgba(Uint8List bytes) {
  try {
    final image = decodeJpeg2000(
      bytes,
      options: Jpeg2000DecodeOptions(
        maxPixels: _maxPixels,
        maxDimension: _maxDimension,
      ),
    );
    return (
      width: image.width,
      height: image.height,
      rgba: expandToRgba(
        image.pixels,
        width: image.width,
        height: image.height,
        components: image.components,
      ),
    );
  } on Jpeg2000Exception catch (e) {
    throw FaceImageException('JPEG2000 decode failed (${e.runtimeType})');
  }
}

/// Converts 1, 2, 3 or 4 bytes-per-pixel data into 4-byte RGBA
Uint8List expandToRgba(
  Uint8List pixels, {
  required int width,
  required int height,
  required int components,
}) {
  final count = width * height;
  if (pixels.length != count * components) {
    throw const FaceImageException('Unexpected pixel layout');
  }

  final out = Uint8List(count * 4);
  switch (components) {
    case 1: // Greyscale
      for (var i = 0; i < count; i++) {
        final g = pixels[i];
        out[i * 4] = g;
        out[i * 4 + 1] = g;
        out[i * 4 + 2] = g;
        out[i * 4 + 3] = 255;
      }
    case 2: // Greyscale + alpha
      for (var i = 0; i < count; i++) {
        final g = pixels[i * 2];
        out[i * 4] = g;
        out[i * 4 + 1] = g;
        out[i * 4 + 2] = g;
        out[i * 4 + 3] = pixels[i * 2 + 1];
      }
    case 3: // RGB
      for (var i = 0; i < count; i++) {
        out[i * 4] = pixels[i * 3];
        out[i * 4 + 1] = pixels[i * 3 + 1];
        out[i * 4 + 2] = pixels[i * 3 + 2];
        out[i * 4 + 3] = 255;
      }
    case 4: // Already RGBA
      out.setAll(0, pixels);
    default:
      throw FaceImageException('Unsupported component count: $components');
  }
  return out;
}

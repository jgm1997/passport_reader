import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:passport_reader/core/image/face_image_decoder.dart';
import 'package:passport_reader/core/image/image_format.dart';

/// Decode the chip's face image (JPEG or JPEG2000) into a dart:ui Image.
Future<ui.Image> decodeFaceImage(Uint8List bytes) async {
  switch (detectImageFormat(bytes)) {
    case DetectedImageFormat.jpeg:
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    case DetectedImageFormat.jpeg2000:
      final decoded = await Isolate.run(() => jpeg2000ToRgba(bytes))
          .timeout(const Duration(seconds: 10));
      return _rgbaToImage(decoded);
    case DetectedImageFormat.unknown:
      throw const FaceImageException('Unknown image format');
  }
}

Future<ui.Image> _rgbaToImage(RgbaImage img) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    img.rgba,
    img.width,
    img.height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  return completer.future;
}

class FacePhoto extends StatefulWidget {
  final Uint8List bytes;
  const FacePhoto({super.key, required this.bytes});

  @override
  State<FacePhoto> createState() => _FacePhotoState();
}

class _FacePhotoState extends State<FacePhoto> {
  ui.Image? _image;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final stopWatch = Stopwatch()..start();
    try {
      final image = await decodeFaceImage(widget.bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      if (kDebugMode) {
        debugPrint(
          'Face decoded in ${stopWatch.elapsedMilliseconds} ms'
          '(${image.width}x${image.height})',
        );
      }
      setState(() => _image = image);
    } catch (e) {
      if (kDebugMode) debugPrint('Face decode failed: ${e.runtimeType}');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const height = 220.0;
    final image = _image;

    if (_failed) {
      return const SizedBox(
        height: height,
        child: Center(child: Text('The photo could not be displayed.')),
      );
    }
    if (image == null) {
      return const SizedBox(
        height: height,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SizedBox(
      height: height,
      child: Center(
        child: AspectRatio(
          aspectRatio: image.width / image.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: RawImage(image: image, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

const Map<DeviceOrientation, int> _deviceOrientationDegrees = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Converts a live camera frame into something ML Kit can read.
/// Returns null if the frame can't be converted (it's then skipped).
InputImage? inputImageFromCameraImage(
  CameraImage image, {
  required CameraDescription camera,
  required DeviceOrientation deviceOrientation,
}) {
  final size = Size(image.width.toDouble(), image.height.toDouble());

  if (Platform.isIOS) {
    // iOS: a single BGRA plane that ML Kit accepts as-is
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: size,
        rotation:
            InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg,
        format: InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // Android: build a grayscale NV21 image from the brightness plane
  final rotation = _androidRotation(camera, deviceOrientation);
  if (rotation == null) return null;

  final yPlane = image.planes.first;
  return InputImage.fromBytes(
    bytes: packLumaAsNv21(
      yPlane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: yPlane.bytesPerRow,
    ),
    metadata: InputImageMetadata(
      size: size,
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: image.width,
    ),
  );
}

/// How far ML Kit must rotate the frame so the test is upright
InputImageRotation? _androidRotation(
  CameraDescription camera,
  DeviceOrientation deviceOrientation,
) {
  final device = _deviceOrientationDegrees[deviceOrientation];
  if (device == null) return null;

  final degrees = camera.lensDirection == CameraLensDirection.front
      ? (camera.sensorOrientation + device) % 360
      : (camera.sensorOrientation - device + 360) % 360;
  return InputImageRotationValue.fromRawValue(degrees);
}

/// Copies the brightness (Y) rows without their padding, then fills the
/// colour (UV) part of NV21 with 128, which means "no color"
Uint8List packLumaAsNv21(
  Uint8List yBytes, {
  required int width,
  required int height,
  required int bytesPerRow,
}) {
  final lumaSize = width * height;
  final out = Uint8List(lumaSize + lumaSize ~/ 2);

  for (var row = 0; row < height; row++) {
    out.setRange(row * width, row * width + width, yBytes, row * bytesPerRow);
  }
  out.fillRange(lumaSize, out.length, 128);
  return out;
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/image/face_image_decoder.dart';
import 'package:passport_reader/features/result/face_photo.dart';

void main() {
  test('expandToRgba keeps RGB order', () {
    final rgba = expandToRgba(
      Uint8List.fromList([255, 0, 0]),
      width: 1,
      height: 1,
      components: 3,
    );
    expect(rgba, [255, 0, 0, 255]);
  });

  testWidgets('a red pixel is still red after becoming a ui.Image', (
    tester,
  ) async {
    final red = (
      width: 1,
      height: 1,
      rgba: Uint8List.fromList([255, 0, 0, 255]),
    );

    final pixels = await tester.runAsync(() async {
      final image = await rgbaToImage(red);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });

    expect(pixels, [255, 0, 0, 255]);
  });
}

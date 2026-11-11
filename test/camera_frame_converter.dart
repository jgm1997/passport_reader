import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/features/mrz_scan/camera_frame_converter.dart';

void main() {
  test('packLumaAsNv21 strips row padding and adds neutral colour', () {
    // A 4×2 image whose rows are padded to 6 bytes (99 = padding).
    final y = Uint8List.fromList([
      1, 2, 3, 4, 99, 99, //
      5, 6, 7, 8, 99, 99, //
    ]);

    final nv21 = packLumaAsNv21(y, width: 4, height: 2, bytesPerRow: 6);

    expect(nv21, [1, 2, 3, 4, 5, 6, 7, 8, 128, 128, 128, 128]);
  });
}

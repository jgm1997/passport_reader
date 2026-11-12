import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/passport/passport_data.dart';

void main() {
  test('wipe() zeroes every byte buffer it owns', () {
    final dg1 = Uint8List.fromList([1, 2, 3]);
    final sod = Uint8List.fromList([4, 5]);
    final photo = Uint8List.fromList([6, 7]);

    final data = PassportData(
      accessProtocol: AccessProtocol.bac,
      documentNumber: 'L898902C3',
      surname: 'ERIKSSON',
      givenNames: 'ANNA MARIA',
      nationality: 'UTO',
      issuingState: 'UTO',
      sex: 'F',
      dateOfBirth: DateTime(1974, 8, 12),
      dateOfExpiry: DateTime(2012, 4, 15),
      rawDataGroups: {1: dg1},
      rawSod: sod,
      photo: photo,
    );

    data.wipe();

    expect(dg1, everyElement(0));
    expect(sod, everyElement(0));
    expect(photo, everyElement(0));
  });
}

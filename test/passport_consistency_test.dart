import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:passport_reader/core/passport/consistency.dart';
import 'package:passport_reader/core/passport/passport_data.dart';

PassportData _chip({String number = 'L898902C3', DateTime? birth}) =>
    PassportData(
      accessProtocol: AccessProtocol.bac,
      documentNumber: number,
      surname: 'ERIKSSON',
      givenNames: 'ANNA MARIA',
      nationality: 'UTO',
      issuingState: 'UTO',
      sex: 'F',
      dateOfBirth: birth ?? DateTime(1974, 8, 12), // local, like dmrtd
      dateOfExpiry: DateTime(2012, 4, 15),
      rawDataGroups: const {},
      rawSod: Uint8List(0),
    );

void main() {
  final key = MrzKey(
    documentNumber: 'L898902C3',
    dateOfBirth: DateTime.utc(1974, 8, 12), // UTC, like our parser
    dateOfExpiry: DateTime.utc(2012, 4, 15),
  );

  test('matching chip has no mismatches (local vs UTC dates)', () {
    expect(findMismatches(_chip(), key), isEmpty);
  });

  test('filler characters in the chip number are ignored', () {
    expect(findMismatches(_chip(number: 'L898902C3<'), key), isEmpty);
  });

  test('detects a different date of birth', () {
    expect(findMismatches(_chip(birth: DateTime(1975, 8, 12)), key), [
      'date of birth',
    ]);
  });
}

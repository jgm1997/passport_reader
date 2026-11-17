import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/asn1/der.dart';

Uint8List _b(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  test('reads an element and its children', () {
    final der = Der.parse(_b([0x30, 0x06, 0x02, 0x01, 0x05, 0x04, 0x01, 0xAA]));
    expect(der.tag, 0x30);
    expect(der.children.map((e) => e.tag), [0x02, 0x04]);
    expect(der.children.first.smallInt, 5);
  });

  test('reads long-form lengths', () {
    final der = Der.parse(_b([0x04, 0x81, 200, ...List.filled(200, 7)]));
    expect(der.value.length, 200);
  });

  test('decodes OIDs', () {
    // 2.23.136.1.1.1 = the ICAO LDS Security Object
    expect(
      Der.parse(_b([0x06, 0x06, 0x67, 0x81, 0x08, 0x01, 0x01, 0x01])).oid,
      '2.23.136.1.1.1',
    );
  });

  test('rejects truncated input and trailing bytes', () {
    expect(() => Der.parse(_b([0x04, 0x05, 1, 2])), throwsFormatException);
    expect(
      () => Der.parse(_b([0x04, 0x01, 0xAA, 0x00])),
      throwsFormatException,
    );
  });

  test('encodeTlv round-trips, including long lengths', () {
    final long = List.filled(300, 1);
    expect(Der.parse(encodeTlv(0x04, long)).value, long);
    expect(encodeTlv(0x80, [1, 2]), [0x80, 0x02, 1, 2]);
  });

  test('toFixedBytes pads with zeros and rejects overflow', () {
    expect(toFixedBytes(BigInt.from(0x0102), 4), [0, 0, 1, 2]);
    expect(() => toFixedBytes(BigInt.from(0x010203), 2), throwsArgumentError);
  });
}

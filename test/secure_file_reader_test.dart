import 'dart:math';
import 'dart:typed_data';

import 'package:dmrtd/internal.dart' show CommandAPDU;
import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/asn1/der.dart';
import 'package:passport_reader/core/passport/secure_file_reader.dart';

void main() {
  group('readBinaryCommand', () {
    test('first read selects by SFI', () {
      expect(readBinaryCommand(sfi: 2, offset: 0, length: 223).toBytes(), [
        0x00,
        0xB0,
        0x82,
        0x00,
        0xDF,
      ]);
    });
    test('later reads put the offset in P1-P2', () {
      expect(readBinaryCommand(offset: 0x1234, length: 223).toBytes(), [
        0x00,
        0xB0,
        0x12,
        0x34,
        0xDF,
      ]);
    });
    test('offsets beyond 15 bits are refused', () {
      expect(
        () => readBinaryCommand(offset: 0x8000, length: 1),
        throwsArgumentError,
      );
    });
  });

  test('tlvTotalLength reads short and long forms', () {
    expect(tlvTotalLength([0x75, 0x10]), 18);
    expect(tlvTotalLength([0x75, 0x82, 0x48, 0x00]), 4 + 0x4800);
    expect(
      () => tlvTotalLength([0x75, 0x84, 1, 2, 3, 4]),
      throwsFormatException,
    );
  });

  test(
    'a file is reassembled exactly, in chunks of at most 223 bytes',
    () async {
      final file = encodeTlv(0x75, List.generate(18000, (i) => i % 251));
      final requests = <(int offset, int length)>[];

      Future<Uint8List> chip(CommandAPDU c) async {
        final offset = (c.p1 & 0x80) != 0 ? c.p2 : (c.p1 << 8) | c.p2;
        requests.add((offset, c.ne));
        return Uint8List.sublistView(
          file,
          offset,
          min(offset + c.ne, file.length),
        );
      }

      final progress = <int>[];
      final read = await readWholeFile(
        chip,
        sfi: 2,
        onProgress: (done, _) => progress.add(done),
      );

      expect(read, file);
      expect(requests.every((r) => r.$2 <= maxSecureChunk), isTrue);
      expect(
        requests.length,
        (file.length / maxSecureChunk).ceil(),
      ); // 81, not 161
      expect(
        requests.last.$1 + requests.last.$2,
        file.length,
      ); // never past the end
      expect(progress.last, file.length);
    },
  );

  test('a hostile length claim is refused before any further reads', () async {
    final lie = Uint8List.fromList([
      0x75,
      0x83,
      0x10,
      0x00,
      0x00,
      ...List.filled(218, 0),
    ]);
    var calls = 0;
    Future<Uint8List> chip(CommandAPDU c) async {
      calls++;
      return lie;
    }

    await expectLater(readWholeFile(chip, sfi: 2), throwsRangeError);
    expect(calls, 1);
  });
}

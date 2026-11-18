import 'dart:math';
import 'dart:typed_data';

import 'package:dmrtd/internal.dart';
import 'package:passport_reader/core/asn1/der.dart';

/// The largest plaintext chuink whose secure-messaging response still fits in
/// a short (256-byte) APDU for BOTH 3DES and AES.
const maxSecureChunk = 223;

/// Sends one READ BINARY and returns the decrypted, MAC-checked data.
typedef ReadBinary = Future<Uint8List> Function(CommandAPDU command);

typedef FileReadProgress = void Function(int bytesRead, int totalBytes);

/// READ BINARY. With [sfi], the file is selected by its short file ID, which
/// also makes it the current file for the following reads (ISO 7816-4).
CommandAPDU readBinaryCommand({
  int? sfi,
  required int offset,
  required int length,
}) {
  if (length < 1 || length > 256) throw ArgumentError.value(length, 'length');
  if (sfi != null) {
    if (sfi < 1 || sfi > 30 || offset > 0xFF) {
      throw ArgumentError('An SFI read starts at offset 0-255 of file 1-30');
    }
    return CommandAPDU(
      cla: 0x00,
      ins: 0xB0,
      p1: 0x80 | sfi,
      p2: offset,
      ne: length,
    );
  }
  if (offset > 0x7FFF) {
    throw ArgumentError.value(
      offset,
      'offset',
      'needs the odd-INS READ BINARY',
    );
  }
  return CommandAPDU(
    cla: 0x00,
    ins: 0xB0,
    p1: offset >> 8,
    p2: offset & 0xFF,
    ne: length,
  );
}

/// Reads a whole elementary file in [chunk]-byte pieces
Future<Uint8List> readWholeFile(
  ReadBinary readBinary, {
  required int sfi,
  int chunk = maxSecureChunk,
  FileReadProgress? onProgress,
}) async {
  final first = await readBinary(
    readBinaryCommand(sfi: sfi, offset: 0, length: chunk),
  );
  final total = tlvTotalLength(first);
  if (total > 0x8000) {
    throw RangeError('File too large for short-offset reads ($total bytes)');
  }

  final out = Uint8List(total);
  var offset = min(first.length, total);
  out.setRange(0, offset, first);
  onProgress?.call(offset, total);

  while (offset < total) {
    final wanted = min(chunk, total - offset);
    final part = await readBinary(
      readBinaryCommand(offset: offset, length: wanted),
    );
    if (part.isEmpty || part.length > wanted) {
      throw StateError('Chip returned ${part.length} bytes, asked for $wanted');
    }
    out.setRange(offset, offset + part.length, part);
    offset += part.length;
    onProgress?.call(offset, total);
  }
  return out;
}

import 'dart:typed_data';

/// One DER element: a tag and its values (ITU-T X.690).
class Der {
  final int tag;
  final Uint8List value;

  const Der(this.tag, this.value);

  /// The elements nested inside a constructed element (SEQUENCE, SET, ...).
  List<Der> get children => Der.parseAll(value);

  /// Parses exactly one element; trailing bytes are an error.
  static Der parse(Uint8List bytes) {
    final (element, end) = _readOne(bytes, 0);
    if (end != bytes.length) {
      throw const FormatException('Trailng data after DER element');
    }
    return element;
  }

  /// Parses consecutive elements until the input ends.
  static List<Der> parseAll(Uint8List bytes) {
    final elements = <Der>[];
    var offset = 0;
    while (offset < bytes.length) {
      final (element, next) = _readOne(bytes, offset);
      elements.add(element);
      offset = next;
    }
    return elements;
  }

  /// OBJECT IDENTIFIER as dotted text, e.g. "0.4.0.127.0.7.2.2.1.2"
  String get oid {
    if (tag != 0x06 || value.isEmpty || (value.last & 0x80) != 0) {
      throw const FormatException('Not a valid OID');
    }
    final arcs = <int>[];
    var current = 0;
    for (final byte in value) {
      current = (current << 7) | (byte & 0x7F);
      if ((byte & 0x80) == 0) {
        arcs.add(current);
        current = 0;
      }
    }
    final first = arcs.first;
    final head = first < 40
        ? [0, first]
        : first < 80
        ? [1, first - 40]
        : [2, first - 80];
    return [...head, ...arcs.skip(1)].join('.');
  }

  /// The value read as an unsigned big-endian number.
  BigInt get unsigned => bytesToUnsigned(value);

  /// A smal INTEGER sucha s a version or key id.
  int get smallInt {
    if (tag != 0x02 || value.isEmpty || value.length > 4) {
      throw const FormatException('Not a small INTEGER');
    }
    return unsigned.toInt();
  }
}

(Der, int) _readOne(Uint8List bytes, int offset) {
  if (offset + 2 > bytes.length) {
    throw const FormatException('Truncated DER element');
  }
  final tag = bytes[offset];
  if ((tag & 0x1F) == 0x1F) {
    throw const FormatException('Multi-byte tags are not supported');
  }

  var index = offset + 1;
  var length = bytes[index++];
  if ((length & 0x80) != 0) {
    final count = length & 0x7F;
    if (count == 0 || count > 3 || index + count > bytes.length) {
      throw const FormatException('Invalid DER length');
    }
    length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | bytes[index++];
    }
  }
  if (index + length > bytes.length) {
    throw const FormatException('Truncated DER element');
  }
  return (
    Der(tag, Uint8List.sublistView(bytes, index, index + length)),
    index + length,
  );
}

/// Builds a TLV: tag, DER length, value.
Uint8List encodeTlv(int tag, List<int> value) {
  final n = value.length;
  final length = n < 0x80
      ? [n]
      : n <= 0xFF
      ? [0x81, n]
      : [0x82, n >> 8, n & 0xFF];
  return Uint8List.fromList([tag, ...length, ...value]);
}

BigInt bytesToUnsigned(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

/// Writes [value] as exactly [length] big-endian bytes (left-padded with zeros).
Uint8List toFixedBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var remaining = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (remaining & BigInt.from(0xFF)).toInt();
    remaining = remaining >> 8;
  }
  if (remaining != BigInt.zero) {
    throw ArgumentError('Value does not fit in $length bytes');
  }
  return out;
}

/// Total size (header + value) of the single-byte-tag TLV that starts [head].
/// Only the first few bytes are needed, which is how we size a file after one read.
int tlvTotalLength(List<int> head) {
  if (head.length < 2 || (head[0] & 0x1F) == 0x1F) {
    throw const FormatException('Unsupported or truncated TLV header');
  }
  final first = head[1];
  if (first < 0x80) return 2 + first;
  final count = first & 0x7F;
  if (count == 0 || count > 3 || head.length < 2 + count) {
    throw const FormatException('Invalid TLV length');
  }
  var length = 0;
  for (var i = 0; i < count; i++) {
    length = (length << 8) | head[2 + i];
  }
  return 2 + count + length;
}

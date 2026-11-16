import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/utils/bytes.dart';

void main() {
  test('decodes hex in either case', () {
    expect(hexToBytes('0aFF'), [0x0a, 0xff]);
  });

  test('rejects odd lengths, signs and non-hex characters', () {
    expect(() => hexToBytes('abc'), throwsFormatException);
    expect(() => hexToBytes('+f'), throwsFormatException);
    expect(() => hexToBytes('zz'), throwsFormatException);
  });

  test('constantTimeEquals compares content and length', () {
    expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
  });
}

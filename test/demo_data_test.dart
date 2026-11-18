import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/demo/demo_data.dart';
import 'package:passport_reader/core/mrz/mrz_parser.dart';

void main() {
  test('the demo MRZ passes every check digit', () {
    final mrz = MrzParser.parseTd3(demoMrzLine1, demoMrzLine2);
    expect(mrz.issuingState, 'UTO');
    expect(mrz.documentNumber, 'L898902C3');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/mrz/mrz_ocr_extractor.dart';

void main() {
  const line1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<';
  const line2 = 'L898902C36UTO7408122F1204159ZE184226B<<<<<10';
  final today = DateTime(2026, 11, 10);

  test('finds line 2 among other OCR text', () {
    final key = MrzOcrExtractor.extract([
      'PASSPORT',
      'UTOPIA',
      line1,
      line2,
    ], now: today);
    expect(key, isNotNull);
    expect(key!.documentNumber, 'L898902C3');
    expect(key.dateOfBirth, DateTime.utc(1974, 8, 12));
    expect(key.dateOfExpiry, DateTime.utc(2012, 4, 15));
  });

  test('repairs typical OCR mistakes', () {
    // A space, '0' in the nationality, 'O' in dates and check digit, and '«'.
    const noisy = 'L898 902C36UT074O8122F12O4159ZE184226B<<«<1O';
    final key = MrzOcrExtractor.extract([line1, noisy], now: today);
    expect(key?.documentNumber, 'L898902C3');
  });

  test('returns null when there is no MRZ', () {
    expect(MrzOcrExtractor.extract([line1, 'random text'], now: today), isNull);
  });

  test('never "repairs" a line with a wrong check digit', () {
    final tampered = line2.replaceFirst('L898902C3', 'L898902C4');
    expect(MrzOcrExtractor.extract([tampered], now: today), isNull);
  });
}

import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:passport_reader/core/mrz/mrz_parser.dart';

/// Finds a valid passport MRZ line 2 inside noisy OCR output
class MrzOcrExtractor {
  /// Positions in line 2 that must be digits
  static const List<int> _digitPositions = [
    9, // document number check digit
    13, 14, 15, 16, 17, 18, 19, // date of birth + check digit
    21, 22, 23, 24, 25, 26, 27, // date of expiry + check digit
    43, // composite check digit
  ];

  /// Positions in line 2 that must be letters (nationality)
  static const List<int> _letterPositions = [10, 11, 12];

  /// Common OCR confusions, by what the position must contain
  static const Map<String, String> _toDigit = {
    'O': '0',
    'Q': '0',
    'D': '0',
    'I': '1',
    'L': '1',
    'Z': '2',
    'S': '5',
    'G': '6',
    'B': '8',
  };
  static const Map<String, String> _toLetter = {
    '0': 'O',
    '1': 'I',
    '2': 'Z',
    '5': 'S',
    '8': 'B',
  };

  /// Returns the chip key from the first OCR line that is a valid line 2,
  /// or null when none is found
  static MrzKey? extract(List<String> ocrLines, {DateTime? now}) {
    for (final raw in ocrLines) {
      final candidate = _clean(raw);
      if (candidate.length != 44) continue;

      try {
        return MrzParser.parseKeyFromLine2(_fixPositions(candidate), now: now);
      } on MrzParseException {
        continue;
      }
    }
    return null;
  }

  static String _clean(String raw) => raw
      .toUpperCase()
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll('«', '<<')
      .replaceAll(RegExp(r'[^A-Z0-9<]'), '<');

  static String _fixPositions(String line) {
    final chars = line.split('');
    for (final i in _digitPositions) {
      chars[i] = _toDigit[chars[i]] ?? chars[i];
    }
    for (final i in _letterPositions) {
      chars[i] = _toLetter[chars[i]] ?? chars[i];
    }
    return chars.join();
  }
}

import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:passport_reader/core/passport/passport_data.dart';

/// Lists the fields where the chip disagrees with the MRZ key we used.
///
/// This proves CONSISTENCY, not AUTHENTICITY. A forger could make both
/// match. Authenticity comes from Passive Authentication.
List<String> findMismatches(PassportData chip, MrzKey key) {
  return [
    if (_clean(chip.documentNumber) != _clean(key.documentNumber))
      'document number',
    if (!_sameDay(chip.dateOfBirth, key.dateOfBirth)) 'date of birth',
    if (!_sameDay(chip.dateOfExpiry, key.dateOfExpiry)) 'date of expiry',
  ];
}

String _clean(String s) => s.replaceAll('<', '').toUpperCase();

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

import 'package:passport_reader/core/mrz/mrz_data.dart';

/// The three MRZ fields need to unlock the passport chip (BAC/PACE)
class MrzKey {
  final String documentNumber;
  final DateTime dateOfBirth;
  final DateTime dateOfExpiry;

  const MrzKey({
    required this.documentNumber,
    required this.dateOfBirth,
    required this.dateOfExpiry,
  });

  /// Builds a key from a fully parsed MRZ (used by the camera)
  factory MrzKey.fromMrzData(MrzData data) => MrzKey(
    documentNumber: data.documentNumber,
    dateOfBirth: data.dateOfBirth,
    dateOfExpiry: data.dateOfExpiry,
  );

  bool isExpired([DateTime? now]) =>
      dateOfExpiry.isBefore(now ?? DateTime.now());

  /// shows only the first and last characters "L********3"
  String get maskedDocumentNumber {
    final n = documentNumber.length;
    if (n <= 2) return '*' * n;
    return '${documentNumber[0]}${'*' * (n - 2)}${documentNumber[n - 1]}';
  }

  /// Never print the real document number, even in logs
  @override
  String toString() => 'MrzKey($maskedDocumentNumber)';
}

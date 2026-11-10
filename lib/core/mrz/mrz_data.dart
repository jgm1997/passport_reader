/// Immutable result of parsing a passport MRZ.
class MrzData {
  final String documentType;
  final String issuingState;
  final String surname;
  final String givenNames;
  final String documentNumber;
  final String nationality;
  final DateTime dateOfBirth;
  final String sex;
  final DateTime dateOfExpiry;
  final String optionalData;

  const MrzData({
    required this.documentType,
    required this.issuingState,
    required this.surname,
    required this.givenNames,
    required this.documentNumber,
    required this.nationality,
    required this.dateOfBirth,
    required this.sex,
    required this.dateOfExpiry,
    required this.optionalData,
  });

  /// True if the passport'sd expiry date is before [now]
  bool isExpired([DateTime? now]) =>
      dateOfExpiry.isBefore(now ?? DateTime.now());

  @override
  String toString() =>
      'MrzData($documentType, $issuingState, $surname, $givenNames, '
      '$documentNumber, born $dateOfBirth, expires $dateOfExpiry)';
}

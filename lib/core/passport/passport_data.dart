import 'dart:typed_data';

enum AccessProtocol { pace, bac }

enum PhotoFormat { jpeg, jpeg2000 }

/// Everything read from the chip.
/// Raw bytes are kept so the server can verify signatures.
class PassportData {
  final AccessProtocol accessProtocol;

  // Parsed from DG1.
  final String documentNumber;
  final String surname;
  final String givenNames;
  final String nationality;
  final String issuingState;
  final String sex;
  final DateTime dateOfBirth;
  final DateTime dateOfExpiry;

  ///Raw bytes of each data group read, keyed by number (1 = DG1, 2 = DG2...).
  final Map<int, Uint8List> rawDataGroups;

  /// Raw EF.SOD: the country's signature over all data group hashes
  final Uint8List rawSod;

  /// Face image from DG2, if present.
  final Uint8List? photo;
  final PhotoFormat? photoFormat;

  const PassportData({
    required this.accessProtocol,
    required this.documentNumber,
    required this.surname,
    required this.givenNames,
    required this.nationality,
    required this.issuingState,
    required this.sex,
    required this.dateOfBirth,
    required this.dateOfExpiry,
    required this.rawDataGroups,
    required this.rawSod,
    this.photo,
    this.photoFormat,
  });

  /// Never print personal data, only the shape of what was read
  @override
  String toString() =>
      'PassportData(${accessProtocol.name}, DGs ${rawDataGroups.keys.toList()})';
}

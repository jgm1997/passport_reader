import 'dart:typed_data';

import 'package:passport_reader/core/utils/bytes.dart';

/// The server's Passive Authentication verdict.
class VerificationResult {
  final bool valid;
  final String? issuingCountry;
  final String? hashAlgorithm;

  /// Data group hashes vouched for by the issuing country (only when valid).
  final Map<int, Uint8List> authenticatedHashes;
  final List<int> verifiedDataGroups;
  final List<String> failures;
  final List<String> warnings;

  const VerificationResult({
    required this.valid,
    required this.issuingCountry,
    required this.hashAlgorithm,
    required this.authenticatedHashes,
    required this.verifiedDataGroups,
    required this.failures,
    required this.warnings,
  });

  /// Parses the JSON body. Throws FormatException if anything is off.
  factory VerificationResult.fromJson(Object? json) {
    if (json case {
      'valid': bool valid,
      'issuingCountry': String? issuingCountry,
      'hashAlgorithm': String? hashAlgorithm,
      'authenticatedHashes': Map<String, dynamic> hashes,
      'verifiedDataGroups': List<dynamic> verified,
      'failures': List<dynamic> failures,
      'warnings': List<dynamic> warnings,
    }) {
      return VerificationResult(
        valid: valid,
        issuingCountry: issuingCountry,
        hashAlgorithm: hashAlgorithm,
        authenticatedHashes: {
          for (final MapEntry(:key, :value) in hashes.entries)
            _dataGroupNumber(key): hexToBytes(_string(value)),
        },
        verifiedDataGroups: _listOf<int>(verified),
        failures: _listOf<String>(failures),
        warnings: _listOf<String>(warnings),
      );
    }
    throw const FormatException('Unexpected verification response');
  }
}

int _dataGroupNumber(String key) {
  final number = int.tryParse(key);
  if (number == null || number < 1 || number > 16) {
    throw FormatException('Invalid data group number: $key');
  }
  return number;
}

String _string(Object? value) =>
    value is String ? value : throw const FormatException('Expected a string');

List<T> _listOf<T>(List<dynamic> items) => [
  for (final item in items)
    item is T ? item : throw const FormatException('Unexpected item type'),
];

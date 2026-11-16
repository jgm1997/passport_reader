import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:passport_reader/core/passport/passport_data.dart';
import 'package:passport_reader/core/verification/verification_result.dart';

enum VerificationFailure {
  unreachable,
  timeout,
  rejectedRequest,
  serverError,
  badResponse,
}

extension VerificationFailureMessage on VerificationFailure {
  String get message => switch (this) {
    VerificationFailure.unreachable =>
      "Couldn't reach the verification server.",
    VerificationFailure.timeout =>
      'The verification server took too long to answer.',
    VerificationFailure.rejectedRequest =>
      'The verification server refused the request.',
    VerificationFailure.serverError =>
      'The verification server had a problem. Try again later.',
    VerificationFailure.badResponse =>
      'The verification server sent an unexpected answer.',
  };
}

class VerificationException implements Exception {
  final VerificationFailure failure;
  const VerificationException(this.failure);

  @override
  String toString() => 'VerificationException(${failure.message})';
}

class VerificationClient {
  final Uri _baseUri;
  final http.Client _http;
  final Duration timeout;

  VerificationClient({
    required Uri baseUri,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = baseUri,
       _http = httpClient ?? http.Client() {
    // Plain HTTP is only accpetable for local development
    if (!kDebugMode && baseUri.scheme != 'https') {
      throw ArgumentError(
        'Release builds must use an https:// verification URL',
      );
    }
  }

  /// Reads the server address given with --dart-define=VERIFY_URL=...
  factory VerificationClient.fromEnvironment() => VerificationClient(
    baseUri: Uri.parse(
      const String.fromEnvironment(
        "VERIFY_URL",
        defaultValue: 'http://localhost:8000',
      ),
    ),
  );

  /// DG2 (the photo) is delberately NOT sent: it's verified on the phone
  static const Set<int> sentDataGroups = {1, 14, 15};

  Future<VerificationResult> verify(PassportData data) async {
    final body = jsonEncode({
      'sod': base64Encode(data.rawSod),
      'dataGroups': {
        for (final MapEntry(:key, :value) in data.rawDataGroups.entries)
          if (sentDataGroups.contains(key)) '$key': base64Encode(value),
      },
    });

    final http.Response response;
    try {
      response = await _http
          .post(
            _baseUri.resolve('/v1/pasive-auth'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const VerificationException(VerificationFailure.timeout);
    } on http.ClientException {
      throw const VerificationException(VerificationFailure.unreachable);
    } on SocketException {
      throw const VerificationException(VerificationFailure.unreachable);
    }

    if (response.statusCode != 200) {
      if (kDebugMode) {
        debugPrint(
          'Verification HTTP ${response.statusCode}: ${response.body}',
        );
      }
      throw VerificationException(
        response.statusCode == 422
            ? VerificationFailure.rejectedRequest
            : VerificationFailure.serverError,
      );
    }

    try {
      return VerificationResult.fromJson(jsonDecode(response.body));
    } on FormatException {
      throw const VerificationException(VerificationFailure.badResponse);
    }
  }

  void close() => _http.close();
}

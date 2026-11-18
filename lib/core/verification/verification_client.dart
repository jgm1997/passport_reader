import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:passport_reader/core/network/pinned_client.dart';
import 'package:passport_reader/core/passport/passport_data.dart';
import 'package:passport_reader/core/security/device_integrity.dart';
import 'package:passport_reader/core/verification/verification_result.dart';

enum VerificationFailure {
  unreachable,
  timeout,
  rejectedRequest,
  serverError,
  badResponse,
  untrustedServer, // TLS failed: the server isn't the one we pinned
  deviceNotTrusted,
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
    VerificationFailure.untrustedServer =>
      "Couldn't establish a trusted connection to the verification server.",
    VerificationFailure.deviceNotTrusted =>
      "This device or app version couldn't be verified as genuine.",
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
  final DeviceIntegrity? _integrity;
  final Duration timeout;

  VerificationClient({
    required Uri baseUri,
    http.Client? httpClient,
    this._integrity,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = _requireHttps(baseUri),
       _http = httpClient ?? createPinnedClient();

  static Uri _requireHttps(Uri uri) {
    if (uri.scheme != 'https') {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'The verification URL must use https://',
      );
    }
    return uri;
  }

  /// Reads the server address given with --dart-define=VERIFY_URL=...
  factory VerificationClient.fromEnvironment() => VerificationClient(
    baseUri: Uri.parse(
      const String.fromEnvironment(
        "VERIFY_URL",
        defaultValue: 'https://localhost:8000',
      ),
    ),
    integrity: PlayIntegrity.fromEnvironment(),
  );

  /// DG2 (the photo) is delberately NOT sent: it's verified on the phone
  static const Set<int> sentDataGroups = {1, 14, 15};

  Future<VerificationResult> verify(PassportData data) async {
    final bodyBytes = utf8.encode(
      jsonEncode({
        'sod': base64Encode(data.rawSod),
        'dataGroups': {
          for (final MapEntry(:key, :value) in data.rawDataGroups.entries)
            if (sentDataGroups.contains(key)) '$key': base64Encode(value),
        },
      }),
    );
    final token = await _integrity
        ?.tokenFor(bodyBytes)
        .timeout(const Duration(seconds: 5), onTimeout: () => null);

    final http.Response response;
    try {
      response = await _http
          .post(
            _baseUri.resolve('/v1/passive-auth'),
            headers: {
              'Content-Type': 'application/json',
              'X-Integrity-Token': ?token,
            },
            body: bodyBytes,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const VerificationException(VerificationFailure.timeout);
    } on HandshakeException {
      throw const VerificationException(VerificationFailure.untrustedServer);
    } on TlsException {
      throw const VerificationException(VerificationFailure.untrustedServer);
    } on http.ClientException {
      throw const VerificationException(VerificationFailure.unreachable);
    } on SocketException {
      throw const VerificationException(VerificationFailure.unreachable);
    }

    if (response.statusCode != 200) {
      if (kDebugMode) debugPrint('Verification HTTP ${response.statusCode}');
      if (response.statusCode == 403) {
        throw const VerificationException(VerificationFailure.deviceNotTrusted);
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

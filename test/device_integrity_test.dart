import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passport_reader/core/security/device_integrity.dart';
import 'package:passport_reader/core/verification/verification_client.dart';

import 'support/tls_test_server.dart';

class _FakeIntegrity implements DeviceIntegrity {
  List<int>? hashedBody;
  @override
  Future<String?> tokenFor(List<int> body) async {
    hashedBody = body;
    return 'fake-token';
  }
}

void main() {
  test('requestHashOf is SHA-256 in hex', () {
    expect(
      requestHashOf(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('the token covers exactly the bytes that are sent', () async {
    final integrity = _FakeIntegrity();
    late http.Request sent;
    final client = VerificationClient(
      baseUri: Uri.parse('https://localhost'),
      integrity: integrity,
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response('{}', 500); // we only care about the request here
      }),
    );

    await expectLater(
      client.verify(samplePassportData()),
      throwsA(isA<VerificationException>()),
    );

    expect(sent.headers['X-Integrity-Token'], 'fake-token');
    expect(sent.bodyBytes, integrity.hashedBody);
    expect(
      jsonDecode(sent.body),
      isA<Map<String, dynamic>>(),
    ); // an object, not a string
  });

  test('a 403 becomes deviceNotTrusted', () async {
    final client = VerificationClient(
      baseUri: Uri.parse('https://localhost'),
      httpClient: MockClient((_) async => http.Response('', 403)),
    );
    await expectLater(
      client.verify(samplePassportData()),
      throwsA(
        isA<VerificationException>().having(
          (e) => e.failure,
          'failure',
          VerificationFailure.deviceNotTrusted,
        ),
      ),
    );
  });
}

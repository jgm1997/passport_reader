import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passport_reader/core/passport/passport_data.dart';
import 'package:passport_reader/core/verification/verification_client.dart';

PassportData _passport() => PassportData(
  accessProtocol: AccessProtocol.bac,
  documentNumber: 'L898902C3',
  surname: 'ERIKSSON',
  givenNames: 'ANNA MARIA',
  nationality: 'UTO',
  issuingState: 'UTO',
  sex: 'F',
  dateOfBirth: DateTime(1974, 8, 12),
  dateOfExpiry: DateTime(2030, 1, 1),
  rawDataGroups: {
    1: Uint8List.fromList([1, 2, 3]),
    2: Uint8List.fromList([4, 5, 6]), // the photo: must never be sent
    15: Uint8List.fromList([7]),
  },
  rawSod: Uint8List.fromList([9, 9]),
);

const _validResponse = {
  'valid': true,
  'issuingCountry': 'UT',
  'hashAlgorithm': 'sha256',
  'authenticatedHashes': {'1': 'aa'},
  'verifiedDataGroups': [1, 15],
  'failures': [],
  'warnings': [],
};

VerificationClient _client(MockClient mock, {Duration? timeout}) =>
    VerificationClient(
      baseUri: Uri.parse('http://localhost:8000'),
      httpClient: mock,
      timeout: timeout ?? const Duration(seconds: 5),
    );

Matcher _fails(VerificationFailure failure) => throwsA(
  isA<VerificationException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  test('sends the SOD, DG1 and DG15, but never the photo', () async {
    late Map<String, dynamic> sent;
    final mock = MockClient((request) async {
      expect(request.url.path, '/v1/passive-auth');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_validResponse), 200);
    });

    final result = await _client(mock).verify(_passport());

    expect(result.valid, isTrue);
    expect(sent['sod'], base64Encode([9, 9]));
    expect((sent['dataGroups'] as Map).keys, unorderedEquals(['1', '15']));
  });

  test('a 422 becomes rejectedRequest', () async {
    final mock = MockClient(
      (_) async => http.Response('{"detail":"bad"}', 422),
    );
    await expectLater(
      _client(mock).verify(_passport()),
      _fails(VerificationFailure.rejectedRequest),
    );
  });

  test('a 500 becomes serverError', () async {
    final mock = MockClient((_) async => http.Response('oops', 500));
    await expectLater(
      _client(mock).verify(_passport()),
      _fails(VerificationFailure.serverError),
    );
  });

  test('no connection becomes unreachable', () async {
    final mock = MockClient(
      (_) async => throw http.ClientException('no route'),
    );
    await expectLater(
      _client(mock).verify(_passport()),
      _fails(VerificationFailure.unreachable),
    );
  });

  test('a slow server becomes timeout', () async {
    final mock = MockClient(
      (_) => Future.delayed(
        const Duration(seconds: 1),
        () => http.Response('{}', 200),
      ),
    );
    await expectLater(
      _client(
        mock,
        timeout: const Duration(milliseconds: 50),
      ).verify(_passport()),
      _fails(VerificationFailure.timeout),
    );
  });

  test('a malformed answer becomes badResponse', () async {
    final mock = MockClient((_) async => http.Response('{"valid":"yes"}', 200));
    await expectLater(
      _client(mock).verify(_passport()),
      _fails(VerificationFailure.badResponse),
    );
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/network/pinned_client.dart';
import 'package:passport_reader/core/passport/passport_data.dart';
import 'package:passport_reader/core/verification/verification_client.dart';

import 'support/tls_test_server.dart';

PassportData samplePassportData() => PassportData(
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

void main() {
  test(
    'a man in the middle is reported as untrustedServer, not unreachable',
    () async {
      final server = await serveTls('evil-localhost');
      final client = VerificationClient(
        baseUri: Uri.parse('https://localhost:${server.port}'),
        httpClient: createPinnedClient(caPems: [readTlsFixture('good-ca.pem')]),
      );
      try {
        await expectLater(
          client.verify(
            samplePassportData(),
          ), // ← the same helper verification_client_test uses
          throwsA(
            isA<VerificationException>().having(
              (e) => e.failure,
              'failure',
              VerificationFailure.untrustedServer,
            ),
          ),
        );
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );
}

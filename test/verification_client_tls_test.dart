import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/network/pinned_client.dart';
import 'package:passport_reader/core/verification/verification_client.dart';

import 'support/tls_test_server.dart';

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

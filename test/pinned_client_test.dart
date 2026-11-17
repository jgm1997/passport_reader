import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:passport_reader/core/network/pinned_client.dart';

import 'support/tls_test_server.dart';

const _fixtures = 'test/fixtures/tls';

/// GETs from a server using [leaf], with a client pinned to [trustedCas].
Future<String> _get(String leaf, List<String> trustedCas) async {
  final server = await serveTls(leaf);
  final client = createPinnedClient(
    caPems: [for (final ca in trustedCas) readTlsFixture('$ca-ca.pem')],
  );
  try {
    final response = await client.get(
      Uri.parse('https://localhost:${server.port}/'),
    );
    return response.body;
  } finally {
    client.close();
    await server.close(force: true);
  }
}

final _refused = throwsA(
  anyOf(isA<HandshakeException>(), isA<http.ClientException>()),
);

void main() {
  setUpAll(() {
    if (!File('$_fixtures/good-ca.pem').existsSync()) {
      fail('TLS fixtures missing: run tool/make_test_certs.sh');
    }
  });

  test(
    'connects to a server whose certificate chains to the pinned CA',
    () async {
      expect(await _get('good-localhost', ['good']), '{}');
    },
  );

  test('refuses a man in the middle with a different CA', () async {
    await expectLater(_get('evil-localhost', ['good']), _refused);
  });

  test('refuses our own CA when the certificate is for another host', () async {
    await expectLater(_get('good-otherhost', ['good']), _refused);
  });

  test('trusts nothing when no CA is pinned (fail closed)', () async {
    await expectLater(_get('good-localhost', []), _refused);
  });
}

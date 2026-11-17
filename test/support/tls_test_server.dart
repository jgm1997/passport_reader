import 'dart:convert';
import 'dart:io';

const tlsFixtures = 'test/fixtures/tls';

String readTlsFixture(String name) =>
    File('$tlsFixtures/$name').readAsStringSync();

/// A real HTTPS server on a random local port, presenting [leaf]'s certificate.
Future<HttpServer> serveTls(String leaf) async {
  final context = SecurityContext()
    ..useCertificateChainBytes(utf8.encode(readTlsFixture('$leaf.pem')))
    ..usePrivateKeyBytes(utf8.encode(readTlsFixture('$leaf.key')));
  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  server.listen(
    (request) => request.response
      ..write('{}')
      ..close(),
  );
  return server;
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:passport_reader/core/passport/passport_data.dart';

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

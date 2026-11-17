import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:passport_reader/core/network/pinned_cas.dart';

/// An HTTP client that trusts ONLY the pinned CAs, never the phone's system CAs.
/// Certificate and hostname checks happen during the TLS handshake,
/// before any request data is sent.
http.Client createPinnedClient({List<String>? caPems}) {
  final context = SecurityContext(withTrustedRoots: false);
  for (final pem in caPems ?? pinnedCaPems) {
    context.setTrustedCertificatesBytes(utf8.encode(pem));
  }

  final client = HttpClient(context: context)
    ..connectionTimeout = const Duration(seconds: 10)
    // Already the default; set explicity so nobody "fixes" a TLS error with `=> true`.
    ..badCertificateCallback = (_, _, _) => false;

  return IOClient(client);
}

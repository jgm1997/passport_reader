import 'package:flutter/foundation.dart' show kReleaseMode;

/// The ONLY certificate authorities this app trusts, and only for its own API.
/// These are public certificates: safe to commit.
///
/// Rotating a CA: add the new one here, ship the update, wait until old app
/// versions are gone, then remove the old one.
List<String> get pinnedCaPems =>
    kReleaseMode ? _productionCas : _developmentCas;

// Passport Reader Dev CA (from backend/scripts/dev_pki.sh). Its key lives on a
// laptop, so release builds must never trust it.
const _developmentCas = <String>[
  '''
-----BEGIN CERTIFICATE-----
MIIBqjCCAVCgAwIBAgIUI/Q/yx9/cGfwSrTvDC6SJFyX6Q4wCgYIKoZIzj0EAwIw
ITEfMB0GA1UEAwwWUGFzc3BvcnQgUmVhZGVyIERldiBDQTAeFw0yNjExMTcxNDMz
MjFaFw0zNjExMTQxNDMzMjFaMCExHzAdBgNVBAMMFlBhc3Nwb3J0IFJlYWRlciBE
ZXYgQ0EwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAR4rMxIgJGQBWDiCJ4SSSOV
f/78fJ/41e3vsK2sEpuX2waB7JD9qakiRxlEMJ7VdufIB3/Towe/tZ8Y9t0TjXSz
o2YwZDAdBgNVHQ4EFgQUTYQlA16MgITctgh/O4vJXxlmzkQwHwYDVR0jBBgwFoAU
TYQlA16MgITctgh/O4vJXxlmzkQwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8B
Af8EBAMCAQYwCgYIKoZIzj0EAwIDSAAwRQIhAOAy7ZUFjQTCFEuzuCmNP3XJ1tu0
ttQNbPDgYf+JBaxSAiASomzoxCGZkO0o2FtZWrpVikjPbLEXWKRniYQj9Xb8Jg==
-----END CERTIFICATE-----
''',
];

// Empty until creating the production CA (offline key, plus a backup CA). An
// empty list trusts nothing: release builds fail closed, they don't fall back.
const _productionCas = <String>[];

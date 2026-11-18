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
  // Windows dev machine, created 2026-11-18.
  '''
-----BEGIN CERTIFICATE-----
MIIBqjCCAVCgAwIBAgIUYdnZ8qVJRUQmw/HPKGPXZRnM7NEwCgYIKoZIzj0EAwIw
ITEfMB0GA1UEAwwWUGFzc3BvcnQgUmVhZGVyIERldiBDQTAeFw0yNjExMTgwODMz
MThaFw0zNjExMTUwODMzMThaMCExHzAdBgNVBAMMFlBhc3Nwb3J0IFJlYWRlciBE
ZXYgQ0EwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASiqVdPl3Dhft1/OMp9vZcl
SHLcNlegG+OW81tuic9ldSR+IdwdH3JpDtazpMg3XINlgByoixE4ViBmVFa9w9FN
o2YwZDAdBgNVHQ4EFgQUIMn9RCxQHwXVBI0e6m1I3ULyzxwwHwYDVR0jBBgwFoAU
IMn9RCxQHwXVBI0e6m1I3ULyzxwwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8B
Af8EBAMCAQYwCgYIKoZIzj0EAwIDSAAwRQIgUD+NkcfT5Jdf+N7vhvaNeeqRZG4b
7OeRZEqY75sa3X8CIQCp6WZFhox16CLKSM6+kMmyOSWB6K/vsin3dF+jn7IErQ==
-----END CERTIFICATE-----
''',
];

// Empty until creating the production CA (offline key, plus a backup CA). An
// empty list trusts nothing: release builds fail closed, they don't fall back.
const _productionCas = <String>[];

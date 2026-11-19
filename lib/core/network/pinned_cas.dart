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
const _productionCas = <String>[
  // Passport Reader primary CA, SHA-256 Fingerprint=B3:06:A8:01:BE:24:E4:92:26:CF:B6:E0:1F:ED:6A:A9:60:DB:44:61:4D:3D:86:14:A2:18:2D:62:25:78:D6:10
  '''
-----BEGIN CERTIFICATE-----
MIIBsjCCAVigAwIBAgIUZZQa5xMdbzZjQIGA0jNptpCKKtEwCgYIKoZIzj0EAwIw
JTEjMCEGA1UEAwwaUGFzc3BvcnQgUmVhZGVyIHByaW1hcnkgQ0EwHhcNMjYxMTE5
MTExOTIxWhcNMzYxMTE2MTExOTIxWjAlMSMwIQYDVQQDDBpQYXNzcG9ydCBSZWFk
ZXIgcHJpbWFyeSBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABHcMcFnqhF/w
H5IDDFzdbxseqz6QxpQPOdk4+/eynWI6vPiq93ThCBxB0YOpKm7vsAI/2aDA5o8K
LYdnIraBzG6jZjBkMB0GA1UdDgQWBBS+HDvsxDO5PeGyh4dAi/ui8gYcdjAfBgNV
HSMEGDAWgBS+HDvsxDO5PeGyh4dAi/ui8gYcdjASBgNVHRMBAf8ECDAGAQH/AgEA
MA4GA1UdDwEB/wQEAwIBBjAKBggqhkjOPQQDAgNIADBFAiEAtBeIvVpA5s+01ts+
d0kqylDGfmd6CpDulXJSBsMAmYcCICYfhCHjIj7aMB5AAAVKnbi87WjCO1ZxcYVk
VPLMKaff
-----END CERTIFICATE-----
''',
  // Passport Reader backup CA, SHA-256 Fingerprint=26:91:9C:89:ED:FB:95:69:C7:F8:4F:0D:7E:12:F8:60:B8:EF:5D:54:BD:46:5E:B7:F6:7A:4A:40:F1:D1:CA:41
  '''
-----BEGIN CERTIFICATE-----
MIIBsDCCAVagAwIBAgIUAlvhpHVnwu58QiL2YLtiG3+6PKcwCgYIKoZIzj0EAwIw
JDEiMCAGA1UEAwwZUGFzc3BvcnQgUmVhZGVyIGJhY2t1cCBDQTAeFw0yNjExMTkx
MTIwMjZaFw0zNjExMTYxMTIwMjZaMCQxIjAgBgNVBAMMGVBhc3Nwb3J0IFJlYWRl
ciBiYWNrdXAgQ0EwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARiOOH5GCOAPP2A
451OE1A81On7i2OC7y1nssKZkwTNiFsp8Iwt+6QDVCL4NhmBrGYDqVaASbKhG+io
oZhDHzoro2YwZDAdBgNVHQ4EFgQU/RGA6VwrTJag2GnYZvQfLKWQvdUwHwYDVR0j
BBgwFoAU/RGA6VwrTJag2GnYZvQfLKWQvdUwEgYDVR0TAQH/BAgwBgEB/wIBADAO
BgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0EAwIDSAAwRQIhAM0jMxWmuhLqreHZ4/f7
KdkxDBL4uPpT/7FFqE7S6Ul4AiBj91MLINRS14zwl3tQxYSXrQeDlkTTT4Msgplh
cXmzUQ==
-----END CERTIFICATE-----
''',
];

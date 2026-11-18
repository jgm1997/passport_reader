import 'dart:math';

import 'package:dmrtd/dmrtd.dart';
import 'package:dmrtd/internal.dart'
    show
        AES_SMCipher,
        AES_SSC,
        CommandAPDU,
        DES_SMCipher,
        DESedeSSC,
        DeriveKey,
        ICCError,
        MrtdApi,
        MrtdSM,
        ResponseAPDU,
        SMError,
        StatusWord;
// KEY_LENGTH isn't exported by dmrtd; safe here because the dependency is pinned.
// ignore: implementation_imports
import 'package:dmrtd/src/lds/asn1ObjectIdentifiers.dart' show KEY_LENGTH;
import 'package:flutter/foundation.dart';
import 'package:passport_reader/core/asn1/der.dart';
import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:pointycastle/export.dart' as pc;

import 'chip_auth_result.dart';
import 'dg14.dart';

class CaChannel {
  final NfcProvider _nfc;
  final MrtdApi _api;

  CaChannel._(this._nfc, this._api);

  /// Strict READ BINARY: no silent recovery, and only data-carrying (so
  /// MAC-checked) success responses are accepted. Same rules as the CA proof.
  Future<Uint8List> readBinary(CommandAPDU command) async {
    final sm = _api.icc.sm!;
    final raw = ResponseAPDU.fromBytes(
      await _nfc.transceive(sm.protect(command).toBytes()),
    );
    if (raw.data?.isEmpty ?? true) {
      throw StateError('Response without data: ${raw.status}');
    }
    final plain = sm.unprotect(raw);
    if (plain.status != StatusWord.success) {
      throw StateError('READ BINARY failed: ${plain.status}');
    }
    return plain.data!;
  }
}

class ChipAuthenticator {
  final NfcProvider _nfc;
  ChipAuthenticator(this._nfc);

  /// Runs Chip Authentication on the already-connected chip. Never throws.
  Future<(ChipAuthResult, CaChannel?)> run(MrzKey key, Uint8List dg14) async {
    final ChipAuthSetup setup;
    try {
      setup = parseDg14(dg14);
    } on Dg14Exception catch (e) {
      return (ChipAuthResult(ChipAuthStatus.notSupported, e.message), null);
    }

    final domain = curveDomain(setup.curve);
    if (domain == null) {
      return (
        ChipAuthResult(
          ChipAuthStatus.notSupported,
          'Unsupported curve (${setup.description})',
        ),
        null,
      );
    }

    var switchedKeys = false;
    var step = 'restarting the session';
    try {
      // 1. A fresh BAC session on the same connection, through an API we control
      final api = MrtdApi(_nfc);
      await _restartSession(api, key);

      // 2. Our ephemeral key pair, and ECDH with the chip's static key from DG14.
      step = 'key agreement';
      final ephemeral = generateEphemeralKeyPair(domain);
      final chipPublicKey = decodeChipPublicKey(domain, setup.publicPoint);
      final sharedSecret = ecdhSharedSecret(
        ephemeral.privateKey,
        chipPublicKey,
      );

      // 3. Send the chip our ephemeral public key (still under the BAC session).
      step = 'sending our key';
      final commands = chipAuthCommands(
        setup,
        ephemeral.publicKey.Q!.getEncoded(false),
      );
      for (final command in commands) {
        final response = (await _send(api, command)).plain;
        if (response.status != StatusWord.success) {
          if (kDebugMode) {
            debugPrint('Chip Authentication refused: ${response.status}');
          }
          return (
            ChipAuthResult(ChipAuthStatus.rejected, 'Chip refused the command'),
            null,
          );
        }
      }

      // 4. Switch to keys only a chip holding DG14's private key can also derive.
      api.icc.sm = _secureMessaging(setup.cipher, sharedSecret);
      switchedKeys = true;

      // 5. The proof.
      step = 'proof';
      final result = await _proveNewKeys(api, setup);
      return (
        result,
        result.status == ChipAuthStatus.passed ? CaChannel._(_nfc, api) : null,
      );
    } on ComProviderError {
      return (
        const ChipAuthResult(ChipAuthStatus.notCompleted, 'Connection lost'),
        null,
      );
    } on ICCError catch (e) {
      if (kDebugMode) {
        debugPrint('Chip Authentication: chip error while $step: ${e.sw}');
      }
      return (
        switchedKeys
            ? const ChipAuthResult(
                ChipAuthStatus.failed,
                'Chip error under the new keys',
              )
            : ChipAuthResult(
                ChipAuthStatus.notCompleted,
                'Chip error while $step',
              ),
        null,
      );
    } on SMError {
      return (
        switchedKeys
            ? const ChipAuthResult(
                ChipAuthStatus.failed,
                'Invalid MAC under the new keys',
              )
            : const ChipAuthResult(
                ChipAuthStatus.notCompleted,
                'Secure messaging error',
              ),
        null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Chip Authentication error: ${e.runtimeType}');
      return (
        switchedKeys
            ? const ChipAuthResult(
                ChipAuthStatus.failed,
                'Unreadable answer under the new keys',
              )
            : ChipAuthResult(
                ChipAuthStatus.notCompleted,
                'Unexpected error while $step',
              ),
        null,
      );
    }
  }

  /// Ends the reader's secure-messaging session and starts a new BAC session.
  ///
  /// A plain command during an active session makes the chip drop that session,
  /// but ICAO allows it to do so by REFUSING the command (e.g. 69 87 / 69 88).
  /// The refusal itself resets the chip, so one retry is expected, not suspicious.
  Future<void> _restartSession(MrtdApi api, MrzKey key) async {
    try {
      await api.selectEMrtdApplication();
    } on ICCError catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Chip Authentication: first SELECT refused (${e.sw}), retrying',
        );
      }
      await api.selectEMrtdApplication();
    }
    await api.initSessionViaBAC(
      DBAKey(key.documentNumber, key.dateOfBirth, key.dateOfExpiry),
    );
  }

  /// Sends a command through the current secure mesaging, WITHOUT any of
  /// dmrtd's automatic session recovery. Returns the raw and decoded response.
  Future<({ResponseAPDU raw, ResponseAPDU plain})> _send(
    MrtdApi api,
    CommandAPDU command,
  ) async {
    final sm = api.icc.sm;
    final wire = sm == null ? command : sm.protect(command);
    final raw = ResponseAPDU.fromBytes(await _nfc.transceive(wire.toBytes()));
    return (raw: raw, plain: sm == null ? raw : sm.unprotect(raw));
  }

  Future<ChipAuthResult> _proveNewKeys(MrtdApi api, ChipAuthSetup setup) async {
    final (:raw, :plain) = await _send(api, proofReadCommand());

    // dmrtd's unprotect() skips the MAC check when a response has no data,
    // so a bare "90 00" from a clone must NOT count as success.
    final macWasChecked = raw.data?.isNotEmpty ?? false;
    final data = plain.data;
    final looksLikeEfCom =
        data != null && data.isNotEmpty && data.first == 0x60;

    if (kDebugMode) {
      debugPrint(
        'Chip Authentication proof: mac=$macWasChecked status=${plain.status} efCom=$looksLikeEfCom',
      );
    }

    if (macWasChecked && plain.status == StatusWord.success && looksLikeEfCom) {
      return ChipAuthResult(ChipAuthStatus.passed, setup.description);
    }
    return const ChipAuthResult(
      ChipAuthStatus.failed,
      'No valid answer under the new keys',
    );
  }
}

// --- Pure helpers (unit-tested) ---

/// The Chip Authentication commands for [setup], carrying our ephemeral key.
List<CommandAPDU> chipAuthCommands(
  ChipAuthSetup setup,
  Uint8List ephemeralPublicKey,
) {
  final keyId = setup.keyId;
  final keyReference = keyId == null
      ? const <int>[]
      : encodeTlv(0x84, _integerBytes(keyId));

  if (setup.cipher == ChipAuthCipher.tripleDes) {
    // MSE:Set KAT with ephemeral public key (tag 0x91).
    return [
      CommandAPDU(
        cla: 0x00,
        ins: 0x22,
        p1: 0x41,
        p2: 0xA6,
        data: Uint8List.fromList([
          ...encodeTlv(0x91, ephemeralPublicKey),
          ...keyReference,
        ]),
      ),
    ];
  }
  // AES: MSE:Set AT selects the protocol, GENERAL AUTHENTICATE sends the key.
  return [
    CommandAPDU(
      cla: 0x00,
      ins: 0x22,
      p1: 0x41,
      p2: 0xA4,
      data: Uint8List.fromList([
        ...encodeTlv(0x80, setup.protocolOidBytes),
        ...keyReference,
      ]),
    ),
    CommandAPDU(
      cla: 0x00,
      ins: 0x86,
      p1: 0x00,
      p2: 0x00,
      // Dynamic Authentication Data (0x7C) wrapping the ephemeral key (0x80).
      data: encodeTlv(0x7C, encodeTlv(0x80, ephemeralPublicKey)),
      ne: 256,
    ),
  ];
}

/// READ BINARY of the first bytes of EF.COM, selected by its short file id.
CommandAPDU proofReadCommand() =>
    CommandAPDU(cla: 0x00, ins: 0xB0, p1: 0x80 | EfCOM.SFI, p2: 0x00, ne: 8);

final Map<String, pc.ECDomainParameters Function()> _namedCurves = {
  '1.3.36.3.3.2.8.1.1.5': pc.ECCurve_brainpoolp224r1.new,
  '1.3.36.3.3.2.8.1.1.7': pc.ECCurve_brainpoolp256r1.new,
  '1.3.36.3.3.2.8.1.1.9': pc.ECCurve_brainpoolp320r1.new,
  '1.3.36.3.3.2.8.1.1.11': pc.ECCurve_brainpoolp384r1.new,
  '1.3.36.3.3.2.8.1.1.13': pc.ECCurve_brainpoolp512r1.new,
  '1.2.840.10045.3.1.7': pc.ECCurve_prime256v1.new,
  '1.3.132.0.34': pc.ECCurve_secp384r1.new,
  '1.3.132.0.35': pc.ECCurve_secp521r1.new,
};

/// The pointycastle curve for [curve], or null if we don't support it.
/// Explicit parameters must match a known curve EXACTLY (a, b, generator x, order).
pc.ECDomainParameters? curveDomain(CurveSpec curve) => switch (curve) {
  NamedCurve(:final oid) => _namedCurves[oid]?.call(),
  ExplicitCurve c => _matchExplicit(c),
};

pc.ECDomainParameters? _matchExplicit(ExplicitCurve c) {
  for (final make in _namedCurves.values) {
    final d = make();
    if (d.n == c.order &&
        d.G.x!.toBigInteger() == c.generatorX &&
        d.curve.a!.toBigInteger() == c.a &&
        d.curve.b!.toBigInteger() == c.b) {
      return d;
    }
  }
  return null;
}

({pc.ECPublicKey publicKey, pc.ECPrivateKey privateKey})
generateEphemeralKeyPair(pc.ECDomainParameters domain) {
  final secure = Random.secure();
  final seed = Uint8List.fromList(
    List.generate(32, (_) => secure.nextInt(256)),
  );
  final random = pc.FortunaRandom()..seed(pc.KeyParameter(seed));
  final generator = pc.ECKeyGenerator()
    ..init(
      pc.ParametersWithRandom(pc.ECKeyGeneratorParameters(domain), random),
    );
  final pair = generator.generateKeyPair();
  return (
    publicKey: pair.publicKey as pc.ECPublicKey,
    privateKey: pair.privateKey as pc.ECPrivateKey,
  );
}

pc.ECPoint decodeChipPublicKey(
  pc.ECDomainParameters domain,
  Uint8List encoded,
) {
  final point = domain.curve.decodePoint(encoded);
  if (point == null || point.isInfinity) {
    throw const FormatException('Invalid chip public key');
  }
  return point;
}

/// ECDH: the x coordinate of (other public point x our private key),
/// as exactly field-size bytes (ICAO 9303 Part 11).
Uint8List ecdhSharedSecret(pc.ECPrivateKey privateKey, pc.ECPoint otherPublic) {
  final shared = (otherPublic * privateKey.d)!;
  if (shared.isInfinity) {
    throw StateError('ECDH produced the point at infinity');
  }
  final fieldBytes = (privateKey.parameters!.curve.fieldSize + 7) ~/ 8;
  return toFixedBytes(shared.x!.toBigInteger()!, fieldBytes);
}

MrtdSM _secureMessaging(ChipAuthCipher cipher, Uint8List k) => switch (cipher) {
  ChipAuthCipher.tripleDes => MrtdSM(
    DES_SMCipher(DeriveKey.desEDE(k), DeriveKey.iso9797MacAlg3(k)),
    DESedeSSC(Uint8List(8)),
  ),
  ChipAuthCipher.aes128 => MrtdSM(
    AES_SMCipher(
      DeriveKey.aes128(k),
      DeriveKey.cmac128(k),
      size: KEY_LENGTH.s128,
    ),
    AES_SSC(),
  ),
  ChipAuthCipher.aes192 => MrtdSM(
    AES_SMCipher(
      DeriveKey.aes192(k),
      DeriveKey.cmac192(k),
      size: KEY_LENGTH.s192,
    ),
    AES_SSC(),
  ),
  ChipAuthCipher.aes256 => MrtdSM(
    AES_SMCipher(
      DeriveKey.aes256(k),
      DeriveKey.cmac256(k),
      size: KEY_LENGTH.s256,
    ),
    AES_SSC(),
  ),
};

List<int> _integerBytes(int value) {
  final out = <int>[];
  var remaining = value;
  do {
    out.insert(0, remaining & 0xFF);
    remaining >>= 8;
  } while (remaining > 0);
  if ((out.first & 0x80) != 0) out.insert(0, 0); // keep DIR INTEGERs positive
  return out;
}

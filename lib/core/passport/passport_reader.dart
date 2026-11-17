// --- Progress ---
import 'package:dmrtd/dmrtd.dart';
import 'package:flutter/foundation.dart';
import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:passport_reader/core/passport/chip_auth_result.dart';
import 'package:passport_reader/core/passport/chip_authentication.dart';
import 'package:passport_reader/core/passport/passport_data.dart';

enum ReadStage {
  waitingForPassport,
  authenticating,
  readingDetails,
  readingPhoto,
  readingSecurityData,
  checkingChip,
  done,
}

typedef ReadProgressCallback = void Function(ReadStage stage, double progress);

// --- Errors ---
enum PassportReadFailure {
  nfcNotSupported,
  nfcDisabled,
  notAPassport,
  timeout,
  tagLost,
  wrongKey,
  cancelled,
  unknown,
}

extension PassportReadFailureMessage on PassportReadFailure {
  String get message => switch (this) {
    PassportReadFailure.nfcNotSupported => 'This phone has no NFC reader.',
    PassportReadFailure.nfcDisabled =>
      'NFC is turned off. Turn it on in Settings and try again.',
    PassportReadFailure.notAPassport =>
      "That doesn't look like a passport chip.",
    PassportReadFailure.timeout =>
      'No passport detected. Place the phone on the photo page and hold still.',
    PassportReadFailure.tagLost =>
      'Connection lost. Keep the phone still until reading finishes.',
    PassportReadFailure.wrongKey =>
      'The chip rejected the details. Check the document number and dates.',
    PassportReadFailure.cancelled => 'Reading was cancelled.',
    PassportReadFailure.unknown =>
      'Something went wrong while reading the chip. Please try again.',
  };
}

class PassportReadException implements Exception {
  final PassportReadFailure failure;
  const PassportReadException(this.failure);

  @override
  String toString() => 'PassportReadException(${failure.name})';
}

// --- Reader ---
class PassportReader {
  final NfcProvider _nfc;

  PassportReader({NfcProvider? nfc}) : _nfc = nfc ?? NfcProvider();

  Future<PassportData> read(
    MrzKey key, {
    ReadProgressCallback? onProgress,
    Duration pollTimeout = const Duration(seconds: 30),
  }) async {
    final stopwatch = Stopwatch()..start();
    final timings = <String, Duration>{};
    var stage = ReadStage.waitingForPassport;
    var stageStart = Duration.zero;

    void report(ReadStage next, double progress) {
      final now = stopwatch.elapsed;
      if (next != stage) {
        timings[stage.name] = now - stageStart; // close the finished stage
        stageStart = now;
      }
      stage = next;
      onProgress?.call(next, progress);
    }

    final status = await NfcProvider.nfcStatus;
    if (status == NfcStatus.notSupported) {
      throw const PassportReadException(PassportReadFailure.nfcNotSupported);
    }
    if (status == NfcStatus.disabled) {
      throw const PassportReadException(PassportReadFailure.nfcDisabled);
    }

    String? iosErrorMessage;
    try {
      // 1. Wait for the passport
      report(ReadStage.waitingForPassport, 0);
      await _connect(pollTimeout);

      // 2. Unlock the chip
      report(ReadStage.authenticating, 0.1);
      final (passport, protocol) = await _openSession(key, pollTimeout);

      // 3. Read the index and the holder's details.
      report(ReadStage.readingDetails, 0.25);
      final com = await passport.readEfCOM();
      final dg1 = await passport.readEfDG1();
      final raw = <int, Uint8List>{1: dg1.toBytes()};

      // 4. Read the photo (the biggest file, so the slowest step)
      Uint8List? photo;
      PhotoFormat? photoFormat;
      if (com.dgTags.contains(EfDG2.TAG)) {
        report(ReadStage.readingPhoto, 0.35);
        final dg2 = await passport.readEfDG2();
        raw[2] = dg2.toBytes();
        photo = dg2.imageData;
        photoFormat = switch (dg2.imageType) {
          ImageType.jpeg => PhotoFormat.jpeg,
          ImageType.jpeg2000 => PhotoFormat.jpeg2000,
          null => null,
        };
      }

      // 5. Read the security files used for verification.
      report(ReadStage.readingSecurityData, 0.8);
      if (com.dgTags.contains(EfDG14.TAG)) {
        final dg14 = await _readOptional(passport.readEfDG14);
        if (dg14 != null) raw[14] = dg14;
      }
      if (com.dgTags.contains(EfDG15.TAG)) {
        final dg15 = await _readOptional(passport.readEfDG15);
        if (dg15 != null) raw[15] = dg15;
      }
      final sod = await passport.readEfSOD();

      // 6. Anti-cloning: prove the chip holds DG14's private key.
      var chipAuthentication = const ChipAuthResult(
        ChipAuthStatus.notSupported,
        'This chip has no DG14',
      );
      final dg14 = raw[14];
      if (dg14 != null) {
        report(ReadStage.checkingChip, 0.9);
        chipAuthentication = await ChipAuthenticator(_nfc).run(key, dg14);
      }
      report(ReadStage.done, 1);

      final mrz = dg1.mrz;
      return PassportData(
        accessProtocol: protocol,
        documentNumber: mrz.documentNumber,
        surname: mrz.lastName,
        givenNames: mrz.firstName,
        nationality: mrz.nationality,
        issuingState: mrz.country,
        sex: mrz.gender,
        dateOfBirth: mrz.dateOfBirth,
        dateOfExpiry: mrz.dateOfExpiry,
        rawDataGroups: raw,
        rawSod: sod.toBytes(),
        photo: photo,
        photoFormat: photoFormat,
        stageTimings: Map.unmodifiable(timings),
        totalReadTime: stopwatch.elapsed,
        chipAuthentication: chipAuthentication,
      );
    } on PassportReadException catch (e) {
      iosErrorMessage = e.failure.message;
      rethrow;
    } catch (e) {
      // Debug builds only. Error text from the chip constains status codes,
      // never personal data, but even so it must not ship in release builds
      if (kDebugMode) {
        debugPrint(
          'Chip read failed during ${stage.name}: ${e.runtimeType}: $e',
        );
      }
      final failure = classifyError(e);
      iosErrorMessage = failure.message;
      throw PassportReadException(failure);
    } finally {
      // Always release the NFC connection, whatever happened
      try {
        await _nfc.disconnect(
          iosAlertMessage: iosErrorMessage == null ? 'Passport read' : '',
          iosErrorMessage: iosErrorMessage,
        );
      } catch (_) {}
    }
  }

  // --- Helpers ---
  Future<void> _connect(Duration timeout) async {
    await _nfc.connect(
      timeout: timeout,
      iosAlertMessage: 'Hold your iPhone near the passport',
    );
    // dmrtd silently drops tags that aren't ISO 7816 smart cards.
    if (!_nfc.isConnected()) {
      throw const PassportReadException(PassportReadFailure.notAPassport);
    }
  }

  /// Tries PACE first (stronger). Falls back to BAC on a fresh connection.
  Future<(Passport, AccessProtocol)> _openSession(
    MrzKey key,
    Duration timeout,
  ) async {
    var passport = Passport(_nfc);

    EfCardAccess? cardAccess;
    try {
      cardAccess = await passport.readEfCardAccess();
    } catch (e) {
      if (e is ComProviderError) rethrow; // Connection lost: stop here.
      // Either the file doesn't exist (BAC-only chip) or dmrtd can't parse it
      // (e.g. PACEInfo without the optional parameterId). Either way: use BAC.
      if (kDebugMode) {
        debugPrint('PACE unavailable (${e.runtimeType}), using BAC');
      }
      cardAccess = null; // No EF.CardAccess: this chip only supports BAC.
    }

    if (cardAccess != null && cardAccess.isPaceInfoSet) {
      try {
        await passport.startSessionPACE(
          _accessKey(key, pace: true),
          cardAccess,
        );
        return (passport, AccessProtocol.pace);
      } catch (e) {
        if (e is ComProviderError) {
          rethrow; // Connection lost: retrying won't help
        }
        // PACE failed: the chip may be in a confused state, so start over
        await _nfc.disconnect();
        await _connect(timeout);
        passport = Passport(_nfc);
      }
    }
    await passport.startSession(_accessKey(key, pace: false));
    return (passport, AccessProtocol.bac);
  }

  DBAKey _accessKey(MrzKey key, {required bool pace}) => DBAKey(
    key.documentNumber,
    key.dateOfBirth,
    key.dateOfExpiry,
    paceMode: pace,
  );

  /// Optional files must not break the whole read if they're missing or odd.
  Future<Uint8List?> _readOptional(
    Future<ElementaryFile> Function() readFile,
  ) async {
    try {
      return (await readFile()).toBytes();
    } catch (e) {
      if (e is ComProviderError) rethrow;
      return null;
    }
  }

  /// dmrtd reports errors as text, so we classify them by their wording
  @visibleForTesting
  static PassportReadFailure classifyError(
    Object error, {
    ReadStage stage = ReadStage.waitingForPassport,
  }) {
    final text = error.toString().toLowerCase();
    if (text.contains('security status not satisfied')) {
      return PassportReadFailure.wrongKey;
    }
    if (text.contains('timeout')) {
      // Before a chip is found, a timeout means "nothing there".
      // After that, it means the connection dropped mid-read.
      return stage == ReadStage.waitingForPassport
          ? PassportReadFailure.timeout
          : PassportReadFailure.tagLost;
    }
    if (text.contains('tag was lost') || text.contains('transceive')) {
      return PassportReadFailure.tagLost;
    }
    if (text.contains('invalidated by user') || text.contains('cancelled')) {
      return PassportReadFailure.wrongKey;
    }
    return PassportReadFailure.unknown;
  }
}

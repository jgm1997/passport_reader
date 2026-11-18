import 'package:flutter/services.dart';
import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:passport_reader/core/passport/chip_auth_result.dart';
import 'package:passport_reader/core/passport/passport_data.dart';
import 'package:passport_reader/core/passport/passport_reader.dart';
import 'package:passport_reader/core/verification/verification_client.dart';
import 'package:passport_reader/core/verification/verification_result.dart';

/// ICAO's specimen holder (see demo_data.dart), as an MRZ key.
final demoMrzKey = MrzKey(
  documentNumber: 'L898902C3',
  dateOfBirth: DateTime.utc(1974, 8, 12),
  dateOfExpiry: DateTime.utc(2034, 4, 15),
);

/// Walks through the real read stages with realistic timing, wouching no NFC.
/// It ignores the key it's given: whatever was scanned or typed, the demo only
/// ever shows the specimen, so real details can't end up in a demo screenshot.
class DemoChipReader implements ChipReader {
  /// 1 = realistic pacing for screenshots; 0 = instant, for tests
  final double timeScale;
  const DemoChipReader({this.timeScale = 1});

  static const _stages = [
    (ReadStage.waitingForPassport, 0.0, 900),
    (ReadStage.authenticating, 0.05, 400),
    (ReadStage.readingDetails, 0.1, 300),
    (ReadStage.readingSecurityData, 0.15, 700),
    (ReadStage.checkingChip, 0.2, 500),
    (ReadStage.readingPhoto, 0.3, 1500),
  ];

  @override
  Future<PassportData> read(
    MrzKey key, {
    ReadProgressCallback? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final timings = <String, Duration>{};

    for (final (stage, progress, ms) in _stages) {
      onProgress?.call(stage, progress);
      final started = stopwatch.elapsed;
      await Future<void>.delayed(
        Duration(milliseconds: (ms * timeScale).round()),
      );
      timings[stage.name] = stopwatch.elapsed - started;
    }
    onProgress?.call(ReadStage.done, 1);

    final face = await rootBundle.load('assets/demo/face.jpg');

    return PassportData(
      accessProtocol: AccessProtocol.pace,
      documentNumber: 'L898902C3',
      surname: 'ERIKSSON',
      givenNames: 'ANNA MARIA',
      nationality: 'UTO',
      issuingState: 'UTO',
      sex: 'F',
      dateOfBirth: DateTime.utc(1974, 8, 12),
      dateOfExpiry: DateTime.utc(2034, 4, 15),
      rawDataGroups: {1: Uint8List(0), 14: Uint8List(0)},
      rawSod: Uint8List(0),
      // A private copy: the result screen's wipe() zeroes it, so it must not
      // be a view into memory owned by the asset system.
      photo: Uint8List.fromList(
        face.buffer.asUint8List(face.offsetInBytes, face.lengthInBytes),
      ),
      photoFormat: PhotoFormat.jpeg,
      stageTimings: Map.unmodifiable(timings),
      totalReadTime: stopwatch.elapsed,
      chipAuthentication: const ChipAuthResult(
        ChipAuthStatus.passed,
        'Demo: no chip was read',
      ),
    );
  }
}

/// Returns a result that renders like a real one but says, in the banner
/// itself, that nothing was verified.
class DemoVerifier implements PassportVerifier {
  const DemoVerifier();

  @override
  void close() {}

  @override
  Future<VerificationResult> verify(PassportData data) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return const VerificationResult(
      valid: true,
      issuingCountry: 'UTO',
      hashAlgorithm: null,
      authenticatedHashes: {},
      verifiedDataGroups: [1, 14],
      failures: [],
      warnings: ['Demo: fictional data, nothing was verified'],
    );
  }
}

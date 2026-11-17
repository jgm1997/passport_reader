import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Proves to the server that a request comes from this app on a genuine device.
abstract interface class DeviceIntegrity {
  /// A token bound to exactly these [body] bytes, or null if attestation
  /// isn't available. Never throws: the SERVER decides what a missing token means.
  Future<String?> tokenFor(List<int> body);
}

/// the hash the server recomputes from the bytes it receives.
String requestHashOf(List<int> body) => sha256.convert(body).toString();

class PlayIntegrity implements DeviceIntegrity {
  final String _cloudProjectNumber;
  Future<void>? _prepared;

  PlayIntegrity(this._cloudProjectNumber);

  factory PlayIntegrity.fromEnvironment() =>
      PlayIntegrity(const String.fromEnvironment('PLAY_CLOUD_PROJECT_NUMBER'));

  static const _channel = MethodChannel('passport_reader/integrity');

  @override
  Future<String?> tokenFor(List<int> body) async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        _cloudProjectNumber.isEmpty) {
      return null; // ios (App Attest) comes later; no project number means not configured
    }
    try {
      await (_prepared ??= _channel.invokeMethod<void>('prepare', {
        'cloudProjectNumber': _cloudProjectNumber,
      }));
      return await _channel.invokeMethod<String>('request', {
        'requestHash': requestHashOf(body),
      });
    } on PlatformException catch (e) {
      _prepared = null; // failed or expired provider: prepare again next time
      if (kDebugMode) {
        debugPrint('Play Integrity unavailable: ${e.code} ${e.message}');
      }
      return null;
    }
  }
}

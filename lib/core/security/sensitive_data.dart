import 'package:material_ui/material_ui.dart';
import 'package:passport_reader/core/passport/passport_data.dart';

/// The passport data currently held by the UI, so it can be erased on demand,
/// even while the app is in the background and no frames are drawn.
abstract final class SensitiveData {
  static final _live = <PassportData>{};

  static void track(PassportData data) => _live.add(data);

  /// Erases one object and stops tracking it (normal screen exit).
  static void release(PassportData data) {
    data.wipe();
    _live.remove(data);
  }

  /// Erasesa everything tracked (timeout). Synchronous: needs no frames.
  static void wipeAll() {
    for (final data in _live) {
      data.wipe();
    }
    _live.clear();
  }

  @visibleForTesting
  static int get liveCount => _live.length;
}

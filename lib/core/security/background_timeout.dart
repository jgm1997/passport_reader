import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:passport_reader/core/security/sensitive_data.dart';

/// After [limit] in the background: erase passport data, then return to the
/// first screen.
class BackgroundTimeout extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final Duration limit;
  final DateTime Function() clock;

  const BackgroundTimeout({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.limit = const Duration(minutes: 2),
    this.clock = DateTime.now,
  });

  @override
  State<BackgroundTimeout> createState() => _BackgroundTimeoutState();
}

class _BackgroundTimeoutState extends State<BackgroundTimeout> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
  }

  void _onHide() {
    _hiddenAt = widget.clock();
    _timer?.cancel();
    _timer = Timer(widget.limit, _expire); // Android: fires while hidden
  }

  void _onShow() {
    _timer?.cancel();
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    // iOS suspends the app, so its timer is never fired: check the clock instead.
    if (hiddenAt != null &&
        widget.clock().difference(hiddenAt) >= widget.limit) {
      _expire();
    }
  }

  void _expire() {
    _timer?.cancel();
    SensitiveData.wipeAll(); // first, and immediately
    widget.navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

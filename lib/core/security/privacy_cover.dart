import 'package:material_ui/material_ui.dart';

/// Hides the app's content whenever it isn't in the foreground, so the
/// app-switcher snapshot shows a neutral cover instead of passport data
class PrivacyCover extends StatefulWidget {
  final Widget child;
  const PrivacyCover({super.key, required this.child});

  @override
  State<PrivacyCover> createState() => _PrivacyCoverState();
}

class _PrivacyCoverState extends State<PrivacyCover> {
  late final AppLifecycleListener _lifecycle;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        final covered = state != AppLifecycleState.resumed;
        if (covered != _covered) setState(() => _covered = covered);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The real app stays in the tree (its state survives), but screen
        // readers can't announce it while it's covered
        ExcludeSemantics(excluding: _covered, child: widget.child),
        if (_covered)
          Positioned.fill(
            key: const ValueKey('privacy-cover'),
            child: AbsorbPointer(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: const Center(child: Icon(Icons.lock_outline, size: 64)),
              ),
            ),
          ),
      ],
    );
  }
}

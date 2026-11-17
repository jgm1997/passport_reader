import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/security/privacy_cover.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => taps++),
    child: Text('taps: $taps'),
  );
}

void main() {
  final cover = find.byKey(const ValueKey('privacy-cover'));

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => PrivacyCover(child: child!),
      home: const Scaffold(body: Center(child: _Counter())),
    ),
  );

  testWidgets('covers the app when it leaves the foreground', (tester) async {
    await pumpApp(tester);
    expect(cover, findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(cover, findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(cover, findsNothing);
  });

  testWidgets('the screen underneath keeps its state', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('taps: 0'));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('taps: 1'), findsOneWidget); // not reset to 0
  });

  testWidgets('taps are blocked while covered', (tester) async {
    await pumpApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    await tester.tap(find.text('taps: 0'), warnIfMissed: false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('taps: 1'), findsNothing);
  });
}

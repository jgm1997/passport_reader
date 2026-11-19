import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:passport_reader/core/passport/passport_data.dart';
import 'package:passport_reader/core/security/background_timeout.dart';
import 'package:passport_reader/core/security/sensitive_data.dart';

PassportData _data() => PassportData(
  accessProtocol: AccessProtocol.bac,
  documentNumber: 'L898902C3',
  surname: 'ERIKSSON',
  givenNames: 'ANNA MARIA',
  nationality: 'UTO',
  issuingState: 'UTO',
  sex: 'F',
  dateOfBirth: DateTime.utc(1974, 8, 12),
  dateOfExpiry: DateTime.utc(2034, 4, 15),
  rawDataGroups: {
    1: Uint8List.fromList([1, 2, 3]),
  },
  rawSod: Uint8List.fromList([4, 5, 6]),
);

void main() {
  late DateTime now;
  late PassportData data;
  final navigatorKey = GlobalKey<NavigatorState>();

  void hide(WidgetTester t) => [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
  ].forEach(t.binding.handleAppLifecycleStateChanged);
  void show(WidgetTester t) => [
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ].forEach(t.binding.handleAppLifecycleStateChanged);

  Future<void> openResult(WidgetTester tester) async {
    now = DateTime(2026, 11, 19, 12);
    data = _data();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => BackgroundTimeout(
          navigatorKey: navigatorKey,
          clock: () => now,
          child: child!,
        ),
        home: const Text('home'),
      ),
    );
    SensitiveData.track(data);
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const Text('result')),
    );
    await tester.pumpAndSettle();
  }

  tearDown(SensitiveData.wipeAll);

  testWidgets('Android: the timer wipes while hidden, without any frames', (
    tester,
  ) async {
    await openResult(tester);
    hide(tester);
    await tester.pump(
      const Duration(minutes: 3),
    ); // the timer fires in the background

    expect(data.rawSod, everyElement(0)); // erased BEFORE the user returns
    expect(SensitiveData.liveCount, 0);

    show(tester);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text('result'), findsNothing);
  });

  testWidgets('iOS: a suspended app is wiped on return by the clock check', (
    tester,
  ) async {
    await openResult(tester);
    hide(tester);
    now = now.add(const Duration(minutes: 3)); // time passed, but no timer ran
    show(tester);
    await tester.pumpAndSettle();

    expect(data.rawDataGroups[1], everyElement(0));
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a short trip to another app keeps the result', (tester) async {
    await openResult(tester);
    hide(tester);
    await tester.pump(const Duration(seconds: 30));
    show(tester);
    await tester.pumpAndSettle();

    expect(data.rawSod, [4, 5, 6]);
    expect(find.text('result'), findsOneWidget);
  });
}

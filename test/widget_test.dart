import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:passport_reader/main.dart';
import 'package:passport_reader/features/mrz_entry/manual_entry_screen.dart';

void main() {
  testWidgets('home screen opens the manual entry form', (tester) async {
    await tester.pumpWidget(const PassportReaderApp());
    expect(find.text('Verify your passport'), findsOneWidget);

    await tester.tap(find.text('Enter details manually'));
    await tester.pumpAndSettle();

    expect(find.text('Passport details'), findsOneWidget);
  });

  testWidgets('submitting an empty form shows every error', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ManualEntryScreen()));

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Enter the document number.'), findsOneWidget);
    expect(find.text('Select your date of birth.'), findsOneWidget);
    expect(find.text('Select the expiry date.'), findsOneWidget);
  });
}

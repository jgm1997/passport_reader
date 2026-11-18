import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/app_services.dart';
import 'package:passport_reader/core/demo/demo_mode.dart';
import 'package:passport_reader/core/demo/demo_services.dart';
import 'package:passport_reader/core/passport/passport_reader.dart';
import 'package:passport_reader/core/verification/verification_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // rootBundle needs it

  test('tests run as the real app, with real services', () {
    expect(kDemoMode, isFalse);
    expect(AppServices.verifier(), isA<VerificationClient>());
  });

  test('the demo reader reports every stage in order, then done', () async {
    final stages = <ReadStage>[];
    final data = await const DemoChipReader(timeScale: 0)
        .read(demoMrzKey, onProgress: (stage, _) => stages.add(stage));

    expect(stages, ReadStage.values); // the enum's own order, ending with done
    expect(data.issuingState, 'UTO');
    expect(data.photo, isNotEmpty);
    expect(data.rawDataGroups.containsKey(2), isFalse);
  });

  test('the demo verifier says so in its result', () async {
    final result = await const DemoVerifier().verify(
      await const DemoChipReader(timeScale: 0).read(demoMrzKey),
    );
    expect(result.warnings.single, contains('nothing was verified'));
  });
}

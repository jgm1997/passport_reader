import 'package:passport_reader/core/demo/demo_mode.dart';
import 'package:passport_reader/core/demo/demo_services.dart';
import 'package:passport_reader/core/passport/passport_reader.dart';
import 'package:passport_reader/core/verification/verification_client.dart';

/// The one place that decides real vs demo. kDemoMode is a compile-time
/// constant, so in the real app the demo branches are tree-shaken away.
abstract final class AppServices {
  static ChipReader chipReader() =>
      kDemoMode ? const DemoChipReader() : PassportReader();

  static PassportVerifier verifier() =>
      kDemoMode ? const DemoVerifier() : VerificationClient.fromEnvironment();
}

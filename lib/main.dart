import 'package:material_ui/material_ui.dart';
import 'package:passport_reader/core/demo/demo_mode.dart';
import 'package:passport_reader/core/security/background_timeout.dart';
import 'package:passport_reader/core/security/privacy_cover.dart';
import 'package:passport_reader/features/home/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PassportReaderApp());
}

class PassportReaderApp extends StatelessWidget {
  const PassportReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    // One navigator for the whole app, so the timeout can return to home.
    final appNavigatorKey = GlobalKey<NavigatorState>();
    return MaterialApp(
      title: 'Passport Reader',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const HomeScreen(),
      builder: (context, child) {
        final app = BackgroundTimeout(
          navigatorKey: appNavigatorKey,
          child: PrivacyCover(child: child!),
        );
        return kDemoMode
            ? Banner(
                message: 'DEMO',
                location: BannerLocation.topEnd,
                child: app,
              )
            : app;
      },
    );
  }
}

import 'package:material_ui/material_ui.dart';
import 'package:passport_reader/features/mrz_entry/manual_entry_screen.dart';
import 'package:passport_reader/features/mrz_scan/mrz_scan_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Passport Reader')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.badge_outlined, size: 96),
              const SizedBox(height: 24),
              Text(
                'Verify your passport',
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'First we read the machine-readable zone (MRZ) on the photo '
                'page. Then you hold the passport against your phone so we '
                'can read its chip.',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MrzScanScreen()),
                ),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Scan MRZ with camera'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ManualEntryScreen()),
                ),
                icon: const Icon(Icons.keyboard_outlined),
                label: const Text('Enter details manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

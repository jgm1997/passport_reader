import 'package:flutter/material.dart';
import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:passport_reader/core/mrz/utils/date_format.dart';

class ReadyToScanScreen extends StatelessWidget {
  final MrzKey mrzKey;
  const ReadyToScanScreen({super.key, required this.mrzKey});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expired = mrzKey.isExpired();

    return Scaffold(
      appBar: AppBar(title: const Text('Read the chip')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.nfc, size: 96),
              const SizedBox(height: 16),
              Text(
                'Check your details',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Document number'),
                      subtitle: Text(mrzKey.maskedDocumentNumber),
                    ),
                    ListTile(
                      title: const Text('Date of birth'),
                      subtitle: Text(formatDate(mrzKey.dateOfBirth)),
                    ),
                    ListTile(
                      title: const Text('Expiry date'),
                      subtitle: Text(formatDate(mrzKey.dateOfExpiry)),
                    ),
                  ],
                ),
              ),
              if (expired) ...[
                const SizedBox(height: 12),
                Text(
                  'This passport has expired. The chip can still be read, '
                  "but it won't be accepted for travel.",
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('NFC chip scan not yet implemented.')),
                ),
                icon: const Icon(Icons.contactless_outlined),
                label: const Text('Start chip read'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

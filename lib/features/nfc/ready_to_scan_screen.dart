import 'package:flutter/material.dart';
import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:passport_reader/core/mrz/utils/date_format.dart';
import 'package:passport_reader/core/passport/passport_reader.dart';
import 'package:passport_reader/features/mrz_entry/manual_entry_screen.dart';
import 'package:passport_reader/features/result/passport_result_screen.dart';

class ReadyToScanScreen extends StatefulWidget {
  final MrzKey mrzKey;
  const ReadyToScanScreen({super.key, required this.mrzKey});

  @override
  State<ReadyToScanScreen> createState() => _ReadyToScanScreenState();
}

class _ReadyToScanScreenState extends State<ReadyToScanScreen> {
  final _reader = PassportReader();
  bool _reading = false;
  ReadStage _stage = ReadStage.waitingForPassport;
  double _progress = 0;
  PassportReadFailure? _failure;

  Future<void> _startRead() async {
    setState(() {
      _reading = true;
      _failure = null;
      _stage = ReadStage.waitingForPassport;
      _progress = 0;
    });

    try {
      final data = await _reader.read(
        widget.mrzKey,
        onProgress: ((stage, progress) {
          if (!mounted) return;
          setState(() {
            _stage = stage;
            _progress = progress;
          });
        }),
      );
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              PassportResultScreen(mrzKey: widget.mrzKey, data: data),
        ),
      );
    } on PassportReadException catch (e) {
      if (mounted) setState(() => _failure = e.failure);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _reenterDetails() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ManualEntryScreen()),
    );
  }

  String _stageLabel(ReadStage stage) => switch (stage) {
    ReadStage.waitingForPassport =>
      'Place your phone on the photo page and hold still...',
    ReadStage.authenticating => 'Unlocking the chip...',
    ReadStage.readingDetails => 'Reading your details...',
    ReadStage.readingPhoto => 'Reading the photo (a few seconds)...',
    ReadStage.readingSecurityData => 'Reading security data...',
    ReadStage.checkingChip => 'Checking the chip is genuine...',
    ReadStage.done => 'Done',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = widget.mrzKey;

    return Scaffold(
      appBar: AppBar(title: const Text('Read the chip')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    const Icon(Icons.contactless_outlined, size: 96),
                    const SizedBox(height: 16),
                    Text(
                      'Open the passport at the photo page, then lay the back '
                      'of oyur phone flat on it. Keep still until it finishes.',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('Document number'),
                            subtitle: Text(key.maskedDocumentNumber),
                          ),
                          ListTile(
                            title: const Text('Date of birth'),
                            subtitle: Text(formatDate(key.dateOfBirth)),
                          ),
                          ListTile(
                            title: const Text('Date of expiry'),
                            subtitle: Text(formatDate(key.dateOfExpiry)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_reading) ...[
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 12),
                      Text(_stageLabel(_stage), textAlign: TextAlign.center),
                    ],
                    if (_failure != null) ...[
                      Text(
                        _failure!.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      if (_failure == PassportReadFailure.wrongKey)
                        TextButton(
                          onPressed: _reenterDetails,
                          child: const Text('Re-enter details'),
                        ),
                    ],
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _reading ? null : _startRead,
                icon: const Icon(Icons.nfc),
                label: Text(_failure == null ? 'Start chip read' : 'Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

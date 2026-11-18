import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:passport_reader/core/app_services.dart';
import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:passport_reader/core/mrz/utils/date_format.dart';
import 'package:passport_reader/core/passport/chip_auth_result.dart';
import 'package:passport_reader/core/passport/consistency.dart';
import 'package:passport_reader/core/passport/passport_data.dart';
import 'package:passport_reader/core/verification/photo_integrity.dart';
import 'package:passport_reader/core/verification/verification_client.dart';
import 'package:passport_reader/core/verification/verification_result.dart';
import 'package:passport_reader/features/result/face_photo.dart';

class PassportResultScreen extends StatefulWidget {
  final MrzKey mrzKey;
  final PassportData data;

  const PassportResultScreen({
    super.key,
    required this.mrzKey,
    required this.data,
  });

  @override
  State<PassportResultScreen> createState() => _PassportResultScreenState();
}

class _PassportResultScreenState extends State<PassportResultScreen> {
  String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';
  late final Future<VerificationResult> _verification;
  bool? _photoSigned; // null untill known (or if there's no photo)

  @override
  void initState() {
    super.initState();
    _verification = _verify();
  }

  Future<VerificationResult> _verify() async {
    final client = AppServices.verifier();
    try {
      final result = await client.verify(widget.data);
      final dg2 = widget.data.rawDataGroups[2];
      if (mounted && result.valid && dg2 != null) {
        setState(() => _photoSigned = photoMatchesSignedHash(dg2, result));
      }
      return result;
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    widget.data.wipe(); // The user left the result: erase when we can.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final mrzKey = widget.mrzKey;
    final mismatches = findMismatches(data, mrzKey);
    final photo = data.photo;
    final photoSigned = _photoSigned;

    return Scaffold(
      appBar: AppBar(title: const Text('Chip read')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _VerificationBanner(future: _verification),
            const SizedBox(height: 12),
            _ChipCheckCard(
              chipAuth: data.chipAuthentication,
              verification: _verification,
            ),
            const SizedBox(height: 12),
            _ConsistencyBanner(mismatches: mismatches),
            const SizedBox(height: 12),
            if (photo != null) ...[
              FacePhoto(bytes: photo),
              if (photoSigned != null) _PhotoBadge(signed: photoSigned),
              const SizedBox(height: 12),
            ],
            _Section(
              title: 'Holder',
              rows: {
                'Surname': data.surname,
                'Given names': data.givenNames,
                'Nationality': data.nationality,
                'Sex': data.sex,
                'Date of birth': formatDate(data.dateOfBirth),
              },
            ),
            _Section(
              title: 'Document',
              rows: {
                'Number': maskDocumentNumber(
                  data.documentNumber.replaceAll('<', ''),
                ),
                'Issuing state': data.issuingState,
                'Expiry date': formatDate(data.dateOfExpiry),
              },
            ),
            _Section(
              title: 'Chip',
              rows: {
                'Access protocol': data.accessProtocol == AccessProtocol.pace
                    ? 'PACE'
                    : 'BAC',
                'Data groups read': data.rawDataGroups.keys
                    .map((n) => 'DG$n')
                    .join(', '),
                'Photo': photo == null
                    ? 'Not present'
                    : '${_kb(photo.length)}, '
                          '${data.photoFormat?.name.toUpperCase() ?? 'unknown format'}',
                'Security object (SOD)': _kb(data.rawSod.length),
                'Chip Authentication': data.chipAuthentication.status.name,
              },
            ),
            const SizedBox(height: 12),
            if (kDebugMode) ...[
              _Section(
                title: 'Read timing (debug)',
                rows: {
                  for (final e in data.stageTimings.entries)
                    e.key: '${e.value.inMilliseconds} ms',
                  'Total': '${data.totalReadTime.inMilliseconds} ms',
                },
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsistencyBanner extends StatelessWidget {
  final List<String> mismatches;
  const _ConsistencyBanner({required this.mismatches});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = mismatches.isEmpty;

    return Card(
      color: ok ? scheme.primaryContainer : scheme.errorContainer,
      child: ListTile(
        leading: Icon(
          ok ? Icons.check_circle_outline : Icons.warning_amber_outlined,
        ),
        title: Text(
          ok ? 'Chip data matches the MRZ' : 'Chip data does not match the MRZ',
        ),
        subtitle: Text(
          ok
              ? 'Consistency check only.'
              : 'Different: ${mismatches.join(', ')}',
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Map<String, String> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final entry in rows.entries)
              ListTile(
                dense: true,
                title: Text(entry.value),
                subtitle: Text(entry.key),
              ),
          ],
        ),
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  final Future<VerificationResult> future;
  const _VerificationBanner({required this.future});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<VerificationResult>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Card(
            child: ListTile(
              leading: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          final error = snapshot.error;
          return Card(
            color: scheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('Not verified'),
              subtitle: Text(
                error is VerificationException
                    ? error.failure.message
                    : 'Verification could not be completed.',
              ),
            ),
          );
        }

        final result = snapshot.requireData;
        if (result.valid) {
          return Card(
            color: scheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(
                'Verified by ${result.issuingCountry ?? 'issuing country'}',
              ),
              subtitle: result.warnings.isEmpty
                  ? null
                  : Text(result.warnings.join('\n')),
            ),
          );
        }
        return Card(
          color: scheme.errorContainer,
          child: ListTile(
            leading: const Icon(Icons.gpp_bad_outlined),
            title: const Text('Verification failed'),
            subtitle: Text(result.failures.join('\n')),
          ),
        );
      },
    );
  }
}

class _PhotoBadge extends StatelessWidget {
  final bool signed;
  const _PhotoBadge({required this.signed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            signed ? Icons.verified : Icons.warning_amber_outlined,
            size: 18,
            color: signed ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              signed
                  ? 'Photo signed by the issuing country'
                  : 'Photo does NOT match the signed data',
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipCheckCard extends StatelessWidget {
  final ChipAuthResult chipAuth;
  final Future<VerificationResult> verification;

  const _ChipCheckCard({required this.chipAuth, required this.verification});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = chipAuth.detail;

    return FutureBuilder<VerificationResult>(
      future: verification,
      builder: (context, snapshot) {
        final serverDone = snapshot.connectionState == ConnectionState.done;
        // The chip's key only means something if DG14 itself is signed by the country.
        final keyVerified =
            snapshot.hasData &&
            snapshot.requireData.valid &&
            snapshot.requireData.verifiedDataGroups.contains(14);

        final (
          IconData icon,
          Color? color,
          String title,
        ) = switch (chipAuth.status) {
          ChipAuthStatus.passed when keyVerified => (
            Icons.verified_user_outlined,
            scheme.primaryContainer,
            'Genuine chip: not a clone',
          ),
          ChipAuthStatus.passed when !serverDone => (
            Icons.hourglass_top,
            null,
            'Chip check passed, waiting for the server...',
          ),
          ChipAuthStatus.passed => (
            Icons.help_outline,
            scheme.surfaceContainerHighest,
            "Chip check passed, but its key wasn't verified by the server...",
          ),
          ChipAuthStatus.failed => (
            Icons.gpp_bad_outlined,
            scheme.errorContainer,
            'Chip Authentication failed: possible clone',
          ),
          ChipAuthStatus.rejected => (
            Icons.block,
            scheme.surfaceContainerHighest,
            'The chip refused Chip Authentication',
          ),
          ChipAuthStatus.notSupported => (
            Icons.info_outline,
            scheme.surfaceContainerHighest,
            'Clone check not available for this chip',
          ),
          ChipAuthStatus.notCompleted => (
            Icons.sync_problem,
            scheme.surfaceContainerHighest,
            "Clone check couldn't be completed",
          ),
        };

        return Card(
          color: color,
          child: ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: detail == null ? null : Text(detail),
          ),
        );
      },
    );
  }
}

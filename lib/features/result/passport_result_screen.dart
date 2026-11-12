import 'package:flutter/material.dart';
import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:passport_reader/core/mrz/utils/date_format.dart';
import 'package:passport_reader/core/passport/consistency.dart';
import 'package:passport_reader/core/passport/passport_data.dart';

class PassportResultScreen extends StatelessWidget {
  final MrzKey mrzKey;
  final PassportData data;

  const PassportResultScreen({
    super.key,
    required this.mrzKey,
    required this.data,
  });

  String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';

  @override
  Widget build(BuildContext context) {
    final mismatches = findMismatches(data, mrzKey);
    final photo = data.photo;

    return Scaffold(
      appBar: AppBar(title: const Text('Chip read')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ConsistencyBanner(mismatches: mismatches),
            const SizedBox(height: 12),
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
              },
            ),
            const SizedBox(height: 12),
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

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:passport_reader/core/mrz/mrz_key.dart';
import 'package:passport_reader/core/mrz/mrz_validators.dart';
import 'package:passport_reader/core/mrz/utils/date_format.dart';
import 'package:passport_reader/features/nfc/ready_to_scan_screen.dart';

class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _documentNumberController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _dateOfExpiryController = TextEditingController();

  DateTime? _dateOfBirth;
  DateTime? _dateOfExpiry;

  @override
  void dispose() {
    _documentNumberController.dispose();
    _dateOfBirthController.dispose();
    _dateOfExpiryController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(today.year - 30),
      firstDate: DateTime(today.year - 120),
      lastDate: today,
      helpText: 'DATE OF BIRTH',
    );
    if (picked == null || !mounted) return;

    setState(() {
      _dateOfBirth = dateOnlyUtc(picked);
      _dateOfBirthController.text = formatDate(_dateOfBirth!);
    });
  }

  Future<void> _pickDateOfExpiry() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfExpiry ?? today,
      firstDate: DateTime(today.year - 15),
      lastDate: DateTime(today.year + 15),
      helpText: 'DATE OF EXPIRY',
    );
    if (picked == null || !mounted) return;

    setState(() {
      _dateOfExpiry = dateOnlyUtc(picked);
      _dateOfExpiryController.text = formatDate(_dateOfExpiry!);
    });
  }

  void _submit() {
    final isValid = _formKey.currentState!.validate();
    if (!isValid) return;

    final mrzKey = MrzKey(
      documentNumber: normalizeDocumentNumber(_documentNumberController.text),
      dateOfBirth: _dateOfBirth!,
      dateOfExpiry: _dateOfExpiry!,
    );

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReadyToScanScreen(mrzKey: mrzKey)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Passport details')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter the details exactly as printed on the photo page '
                  'of your passport.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _documentNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Document number',
                    helperText: 'Usually at the top right of the photo page',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 9,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  ],
                  textInputAction: TextInputAction.next,
                  validator: validateDocumentNumber,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _dateOfBirthController,
                  readOnly: true,
                  onTap: _pickDateOfBirth,
                  decoration: const InputDecoration(
                    labelText: 'Date of birth',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (_) =>
                      validateDateOfBirth(_dateOfBirth, today: DateTime.now()),
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _dateOfExpiryController,
                  readOnly: true,
                  onTap: _pickDateOfExpiry,
                  decoration: const InputDecoration(
                    labelText: 'Expiry date',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (_) => validateDateOfExpiry(
                    _dateOfExpiry,
                    dateOfBirth: _dateOfBirth,
                  ),
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 32),
                FilledButton(onPressed: _submit, child: const Text('Continue')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

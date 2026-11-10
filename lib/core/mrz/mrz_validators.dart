final RegExp _documentNumberPattern = RegExp(r'^[A-Z0-9]{1,9}$');

/// Uppercases and strips spaces so " l898 902c3" becomes "L898902C3"
String normalizeDocumentNumber(String input) =>
    input.trim().toUpperCase().replaceAll(' ', '');

/// Return an error message, or null when the value is valid
String? validateDocumentNumber(String? input) {
  final value = normalizeDocumentNumber(input ?? '');
  if (value.isEmpty) return 'Enter the document number.';
  if (!_documentNumberPattern.hasMatch(value)) {
    return 'Use up to 9 letters and digits, as printed.';
  }
  return null;
}

String? validateDateOfBirth(DateTime? dateOfBirth, {required DateTime today}) {
  if (dateOfBirth == null) return 'Select your date of birth.';
  if (dateOfBirth.isAfter(today)) {
    return "Date of birth can't be in the future.";
  }
  return null;
}

String? validateDateOfExpiry(DateTime? dateOfExpiry, {DateTime? dateOfBirth}) {
  if (dateOfExpiry == null) return 'Select the expiry date.';
  if (dateOfBirth != null && !dateOfExpiry.isAfter(dateOfBirth)) {
    return "Expiry date must be after the date of birth.";
  }
  return null;
}

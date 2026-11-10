/// Formats a date as YYY-MM-DD without needing the intl package
String formatDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');

  return '$y-$m-$day';
}

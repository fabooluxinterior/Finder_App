/// Minimal RFC 4180 CSV writer (quotes fields that need it). Cells starting
/// with = + - @ are prefixed with ' so spreadsheets don't run them as formulas.
String toCsv(List<List<Object?>> rows) => rows.map((r) => r.map(_cell).join(',')).join('\r\n');

String _cell(Object? v) {
  var s = v == null
      ? ''
      : v is DateTime
      ? v.toUtc().toIso8601String()
      : '$v';
  if (s.isNotEmpty && '=+-@'.contains(s[0])) s = "'$s";
  return RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}

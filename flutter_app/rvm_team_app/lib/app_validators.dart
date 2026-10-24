// Client-side checks for the values people type in: mobile numbers, emails,
// pincodes, bank fields and dates of birth. The backend still owns the final
// say; these only stop obviously wrong values before they are sent.

/// `name@host.tld` — good enough to catch typos, not a full RFC parse.
bool isValidEmail(String value) {
  final v = value.trim();
  if (v.isEmpty || v.length > 254 || v.contains(' ')) return false;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v);
}

/// Strips spaces, dashes and an optional +91/91/0 prefix, then returns the
/// 10-digit number — or null when the input is not a valid Indian mobile.
String? normalizePhone10(String value) {
  var digits = value.replaceAll(RegExp(r'[\s\-()]'), '');
  if (digits.startsWith('+')) digits = digits.substring(1);
  if (!RegExp(r'^\d+$').hasMatch(digits)) return null;
  if (digits.length == 12 && digits.startsWith('91')) {
    digits = digits.substring(2);
  } else if (digits.length == 11 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (digits.length != 10) return null;
  // Indian mobiles start with 6-9.
  if (!RegExp(r'^[6-9]').hasMatch(digits)) return null;
  return digits;
}

bool isValidPhone10(String value) => normalizePhone10(value) != null;

/// True when the text looks like a phone-number attempt (only digits, spaces,
/// dashes, parentheses and an optional leading +), as opposed to a username
/// or an employee code.
bool isPhoneLike(String value) {
  final v = value.trim();
  return v.isNotEmpty && RegExp(r'^[+\d][\d\s\-()]*$').hasMatch(v);
}

/// Smart check for "username or phone" / "phone, email or code" fields:
/// an @-value must be a valid email, a phone-looking value must be a valid
/// 10-digit mobile, anything else (username, employee code) passes through to
/// the server. Returns the error message, or null when the value is fine.
String? validateIdentifier(String value, {required String emptyMessage}) {
  final v = value.trim();
  if (v.isEmpty) return emptyMessage;
  if (v.contains('@') && !isValidEmail(v)) {
    return 'Enter a valid email address.';
  }
  if (!v.contains('@') && isPhoneLike(v) && !isValidPhone10(v)) {
    return 'Enter a valid 10-digit mobile number.';
  }
  return null;
}

bool isValidPincode(String value) =>
    RegExp(r'^\d{6}$').hasMatch(value.trim());

/// Real IFSC shape: 4 bank letters, a zero, then 6 branch characters.
bool isValidIfsc(String value) =>
    RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(value.trim().toUpperCase());

/// Indian account numbers are digits, usually 9-18 long.
bool isValidAccountNumber(String value) =>
    RegExp(r'^\d{9,18}$').hasMatch(value.replaceAll(' ', '').trim());

/// `handle@bank` — the handle needs at least 2 characters.
bool isValidUpi(String value) =>
    RegExp(r'^[\w.\-]{2,}@[A-Za-z]{2,}$').hasMatch(value.trim());

/// Strict YYYY-MM-DD that is also a real calendar date.
bool isValidIsoDate(String value) {
  final v = value.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return false;
  final parsed = DateTime.tryParse(v);
  if (parsed == null) return false;
  final back =
      '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  return back == v;
}

/// A date of birth: a real date, not in the future, within a sane range.
bool isValidDob(String value, {DateTime? now}) {
  if (!isValidIsoDate(value)) return false;
  final date = DateTime.parse(value.trim());
  final today = now ?? DateTime.now();
  final earliest = DateTime(today.year - 100, today.month, today.day);
  final latest = DateTime(today.year, today.month, today.day);
  return !date.isBefore(earliest) && !date.isAfter(latest);
}

String toIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

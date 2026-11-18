/// Takes personal data out of anything headed for a log line or a crash report
/// (team_app #61): phone-like digit runs, and the values of name and phone
/// keys.
///
/// A name cannot be recognised in free text, so it is removed only where it
/// sits under a name key: `name=…` in a query, `"full_name": "…"` in JSON, a
/// map entry. A digit run of ten or more digits is removed wherever it is: a
/// mobile number (`9999999999`, `+91 99999 99999`, `999-999-9999`), and with it
/// other long numbers such as an account number or a millisecond timestamp.
/// Dates, times, short ids and status codes stay readable.
///
/// It only ever removes data, so it is always on.
abstract final class Redact {
  /// What a removed value is replaced with.
  static const mask = '[redacted]';

  /// Keys that end in "name" but never hold a person's name.
  static const _notPersonal = {
    'filename',
    'hostname',
    'devicename',
    'osname',
    'branchname',
    'locationname',
    'batchname',
    'coursename',
    'categoryname',
    'channelname',
    'bankname',
    'companyname',
    'collegename',
    'routename',
    'typename',
    'eventname',
    'modulename',
    'rolename',
  };

  static const _exactKeys = {'tel', 'contact', 'contactno', 'contactnumber'};

  static const _keyStems = ['name', 'phone', 'mobile', 'whatsapp', 'msisdn'];

  /// `key=value`, `key: value` or `"key": "value"` for a name or phone key. An
  /// unquoted value runs to the next delimiter, double quote or `key:`; an
  /// apostrophe does not end it, so a name with one is removed whole.
  static final _pair = RegExp(
    r'''(?<![A-Za-z0-9_\-])(["']?)([A-Za-z0-9_\-]*(?:name|phone|mobile|whatsapp|msisdn)[A-Za-z0-9_\-]*|tel|contact(?:_?n(?:o|umber))?)\1(\s*[:=]\s*)("[^"]*"|'[^']*'|(?:(?!\s+[A-Za-z_][A-Za-z0-9_\-]*\s*[:=])[^,&;}\])\r\n"])+)''',
    caseSensitive: false,
  );

  /// Ten or more digits in a row, with an optional leading `+`.
  static final _longDigits = RegExp(r'(?<!\d)\+?\d{10,}(?!\d)');

  /// Digit groups of three or more, joined by one space or dash, after an
  /// optional country or trunk prefix: `98765 43210`, `+91 98765-43210`,
  /// `987-654-3210`. Groups of one or two digits (dates, times) never join.
  static final _groupedDigits =
      RegExp(r'(?<!\d)\+?(?:\d{1,3}[ \-])?\d{3,}(?:[ \-]\d{3,})+(?!\d)');

  /// [input] with the values of name and phone keys and every phone-like
  /// digit run replaced by [mask].
  static String text(String input) {
    final pairs = input.replaceAllMapped(_pair, (m) {
      final value = m[4]!;
      final quoted = value.length >= 2 &&
          (value.startsWith('"') || value.startsWith("'"));
      final inner = quoted ? value.substring(1, value.length - 1) : value;
      if (!isSensitiveKey(m[2]!) || inner.trim().isEmpty) return m[0]!;
      final masked = quoted ? '${value[0]}$mask${value[0]}' : mask;
      return '${m[1]}${m[2]}${m[1]}${m[3]}$masked';
    });
    return pairs
        .replaceAll(_longDigits, mask)
        .replaceAllMapped(_groupedDigits, (m) {
      final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
      return digits.length >= 10 ? mask : m[0]!;
    });
  }

  /// A copy of [input] safe to log: a name or phone key's value becomes
  /// [mask], and every other value is cleaned with [text], nested maps and
  /// lists included.
  static Map<String, Object?> map(Map<Object?, Object?> input) => {
        for (final entry in input.entries)
          '${entry.key}': isSensitiveKey('${entry.key}') && entry.value != null
              ? mask
              : _value(entry.value),
      };

  /// [uri] as text for a log line. The path and query are decoded first, so a
  /// number sent as `%2B91+99999+99999` is still found.
  static String uri(Uri uri) {
    String shown;
    try {
      final query =
          uri.hasQuery ? '?${Uri.decodeQueryComponent(uri.query)}' : '';
      final origin = uri.hasScheme ? '${uri.scheme}://${uri.authority}' : '';
      shown = '$origin${Uri.decodeFull(uri.path)}$query';
    } catch (_) {
      shown = '$uri';
    }
    return text(shown);
  }

  /// True for a key whose value is a person's name or phone number.
  static bool isSensitiveKey(String key) {
    final k = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (k.isEmpty || _notPersonal.contains(k)) return false;
    return _exactKeys.contains(k) || _keyStems.any(k.contains);
  }

  static Object? _value(Object? value) => switch (value) {
        final String s => text(s),
        final Map<Object?, Object?> m => map(m),
        final Iterable<Object?> list => [for (final v in list) _value(v)],
        final num n => text('$n') == '$n' ? n : mask,
        _ => value,
      };
}

import 'package:core_network/core_network.dart';
import 'package:test/test.dart';

// Only made-up values: repeated-digit numbers and "Test …" names.
const _m = Redact.mask;

void main() {
  group('Redact.text removes phone-like digit runs', () {
    final cases = <String, String>{
      '9999999999': _m,
      'Call 9999999999 now': 'Call $_m now',
      '+919999999999': _m,
      '+91 99999 99999': _m,
      '+91-99999-99999': _m,
      '+91 99999-99999': _m,
      '0 99999 99999': _m,
      '09999999999': _m,
      '999-999-9999': _m,
      '(+91) 99999 99999': '(+91) $_m',
      'user9999999999': 'user$_m',
      '/api/leads/9999999999/calls': '/api/leads/$_m/calls',
      'a 8888 8888 8888 b': 'a $_m b',
    };
    cases.forEach((input, expected) {
      test(input, () => expect(Redact.text(input), expected));
    });
  });

  group('Redact.text keeps what is not personal', () {
    for (final input in [
      '2026-11-12',
      '2026-11-12 10:30:45',
      '12-11-2026 at 09:05',
      '[rvm.net] ✗ 401 GET /api/me (523ms) (badResponse)',
      'GET /api/batches/12345',
      'build 0.1.5+6',
      '₹12,34,567.89',
      '10.0.2.2:3000',
      'id 123456789',
      '0b1c2d3e-4f50-4a6b-8c7d-9e0f1a2b3c4d',
      'Name is required.',
      'name=',
      'Your session has expired. Please sign in again.',
    ]) {
      test(input, () => expect(Redact.text(input), input));
    }
  });

  group('Redact.text removes the values of name and phone keys', () {
    final cases = <String, String>{
      'name=Test Student&batch=7': 'name=$_m&batch=7',
      '{"full_name":"Test Student","role":"faculty"}':
          '{"full_name":"$_m","role":"faculty"}',
      "{'lead_name': 'Test Lead'}": "{'lead_name': '$_m'}",
      '{name: Test Student, phone: 9999999999, id: 7}':
          '{name: $_m, phone: $_m, id: 7}',
      'location_name=Faridabad&name=Test Student':
          'location_name=Faridabad&name=$_m',
      'lead_name: Test Lead phone: 9999999999': 'lead_name: $_m phone: $_m',
      'username: test.user': 'username: $_m',
      'emergency_phone=8888888888': 'emergency_phone=$_m',
      'contact_no=Test Desk': 'contact_no=$_m',
      'https://scheduler.test/api/students?phone=9999999999&page=2':
          'https://scheduler.test/api/students?phone=$_m&page=2',
      'route "/leads?name=Test Lead" could not be opened':
          'route "/leads?name=$_m" could not be opened',
      "name=Test O'Test&x=1": 'name=$_m&x=1',
    };
    cases.forEach((input, expected) {
      test(input, () => expect(Redact.text(input), expected));
    });
  });

  test('Redact.map masks name and phone keys and cleans every other value', () {
    final cleaned = Redact.map({
      'name': 'Test Student',
      'phone': '9999999999',
      'role': 'faculty',
      'note': 'call 9999999999 after 5',
      'count': 3,
      'big': 9999999999,
      'missing_name': null,
      'nested': {'mobile': '9999999999', 'branch_name': 'Faridabad'},
      'rows': [
        '9999999999',
        {'father_name': 'Test Parent', 'day': '2026-11-12'},
      ],
    });

    expect(cleaned, {
      'name': _m,
      'phone': _m,
      'role': 'faculty',
      'note': 'call $_m after 5',
      'count': 3,
      'big': _m,
      'missing_name': null,
      'nested': {'mobile': _m, 'branch_name': 'Faridabad'},
      'rows': [
        _m,
        {'father_name': _m, 'day': '2026-11-12'},
      ],
    });
  });

  group('Redact.uri', () {
    test('decodes the path and query before cleaning them', () {
      final uri = Uri.parse('https://scheduler.test/api/leads/9999999999'
          '?name=Test%20Student&q=%2B91+99999+99999&page=2');
      expect(Redact.uri(uri),
          'https://scheduler.test/api/leads/$_m?name=$_m&q=$_m&page=2');
    });

    test('keeps a URL with nothing personal as it is', () {
      final uri = Uri.parse('https://team-api.test/api/ess/me/capabilities');
      expect(Redact.uri(uri), '$uri');
    });

    test('never throws on a malformed escape', () {
      final uri = Uri.parse('https://x.test/a?b=%E0%A4&phone=9999999999');
      expect(Redact.uri(uri), isNot(contains('9999999999')));
    });
  });

  test('isSensitiveKey', () {
    for (final key in [
      'name',
      'full_name',
      'firstName',
      'username',
      'father_name',
      'student_name',
      'consent_name',
      'phone',
      'mobile_no',
      'alt_phone',
      'whatsappNumber',
      'contact',
      'contact_number',
      'tel',
    ]) {
      expect(Redact.isSensitiveKey(key), isTrue, reason: key);
    }
    for (final key in [
      'location_name',
      'locationName',
      'branch_name',
      'file_name',
      'device_name',
      'os_name',
      'bank_name',
      'company_name',
      'college_name',
      'role',
      'id',
      'status',
      '',
    ]) {
      expect(Redact.isSensitiveKey(key), isFalse, reason: key);
    }
  });
}

import 'dart:io';

import 'package:core_network/core_network.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/app_crash.dart';
import 'package:rvm_team_app/push/push_service.dart';

// Only made-up values: repeated-digit numbers and "Test …" names.
void main() {
  late List<String> printed;
  late DebugPrintCallback original;

  setUp(() {
    printed = [];
    original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => printed.add('$message');
  });

  tearDown(() => debugPrint = original);

  group('crash reports', () {
    test('an error line keeps its cause without the number', () async {
      await CrashReporter.record(
          const BadResponseFailure('The number 9999999999 is already on a lead.',
              statusCode: 409),
          null);

      expect(printed.single, contains('is already on a lead'));
      expect(printed.single, isNot(contains('9999999999')));
    });

    test('a reason is cleaned too', () async {
      await CrashReporter.record(StateError('refused'), null,
          reason: 'GET /leads?phone=9999999999&name=Test Lead');

      expect(printed.single, isNot(contains('9999999999')));
      expect(printed.single, isNot(contains('Test Lead')));
    });

    test('custom keys never carry a number or a name', () {
      expect(CrashReporter.safeKeyValue('last_api', 'GET /api/leads/9999999999 -> 404'),
          'GET /api/leads/${Redact.mask} -> 404');
      expect(CrashReporter.safeKeyValue('lead_name', 'Test Lead'), Redact.mask);
      expect(CrashReporter.safeKeyValue('phone', '9999999999'), Redact.mask);
      expect(CrashReporter.safeKeyValue('device_model', 'Pixel 7'), 'Pixel 7');
      expect(CrashReporter.safeKeyValue('device_name', 'google panther'),
          'google panther');
      expect(CrashReporter.safeKeyValue('os_version', '14 (SDK 34)'),
          '14 (SDK 34)');
    });
  });

  group('push debug lines', () {
    test('carry no number or name', () {
      pushLog('RVM push route "/leads/9999999999?name=Test Lead" '
          'could not be opened: refused');

      expect(printed.single, isNot(contains('9999999999')));
      expect(printed.single, isNot(contains('Test Lead')));
      expect(printed.single, contains('could not be opened'));
    });

    test('go only through pushLog, and the FCM token is never printed', () {
      final source = File('lib/push/push_service.dart').readAsStringSync();

      expect(source, isNot(contains('FCM token:')));
      expect(RegExp(r'debugPrint\(').allMatches(source), hasLength(1),
          reason: 'the one inside pushLog');
    });
  });
}

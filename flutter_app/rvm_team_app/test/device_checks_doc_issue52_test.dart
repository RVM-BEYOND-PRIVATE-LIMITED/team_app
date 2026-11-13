import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/router/module_routes.dart';

/// team_app #52, item 13: the device checklist (docs/device-checks.md) has a
/// row for every screen that blocks capture, so a module marked sensitive
/// cannot ship without one, and the README links it.
void main() {
  late String doc;

  setUpAll(() {
    final file = File('docs/device-checks.md');
    if (!file.existsSync()) {
      fail('Run this test from flutter_app/rvm_team_app (flutter test does): '
          'docs/device-checks.md is read from there.');
    }
    doc = file.readAsStringSync();
  });

  /// The table rows of [doc] (lines that start with `|`).
  List<String> rows() =>
      doc.split('\n').where((l) => l.trimLeft().startsWith('|')).toList();

  test('has a result row for every module marked sensitive', () {
    final sensitive = [
      for (final m in TeamModule.values)
        if (m.sensitive) m.routePrefix,
    ];
    // An empty list would make the check below pass on nothing.
    expect(sensitive, isNotEmpty);
    for (final prefix in sensitive) {
      expect(rows().where((r) => r.contains('| `$prefix` |')), hasLength(1),
          reason: 'docs/device-checks.md needs one result row for $prefix');
    }
  });

  test('checks the class roster with its switch on', () {
    expect(
        rows().where((r) => r.contains('`/work/batch/:id/mark`')), isNotEmpty);
    expect(doc, contains('flutter run --dart-define=SECURE_ROSTER=true'));
    expect(doc, contains('adb exec-out screencap -p'));
    expect(doc, contains('adb shell screenrecord'));
    expect(doc, contains('KEYCODE_APP_SWITCH'));
  });

  test('is linked from the README', () {
    expect(File('README.md').readAsStringSync(),
        contains('(docs/device-checks.md)'));
  });
}

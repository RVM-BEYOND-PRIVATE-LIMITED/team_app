import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/router/module_routes.dart';

/// team_app #52, item 10 (and check 8's no-export half): no share, download
/// or print action on any module list, and a test that fails when share_plus
/// is imported under a sensitive module.
///
/// A module's screens live in `lib/features/<module>/` (#51 starts
/// `lib/features/crm`). None of those folders exists yet, so today this pins
/// the screens that do exist: the class roster, which is sensitive (#52
/// question 3), and share_plus staying on the ID card screen alone.

/// Packages that share, print or save a file out of the app.
const _exportPackages = [
  'share_plus',
  'printing',
  'pdf',
  'csv',
  'excel',
  'file_saver',
  'open_filex',
];

/// A share, download or print control drawn on screen.
final _exportIcon = RegExp(
    r'Icons\.(share|ios_share|download|file_download|print|save_alt|picture_as_pdf)\w*');

/// Sensitive screens that are not under a module folder.
const _sensitiveFiles = ['lib/features/work/mark_attendance_screen.dart'];

/// The one screen that may share today: the person's own ID card link.
const _shareAllowed = {'lib/features/me/id_card_screen.dart'};

/// Why [source] exports, one line each; empty when it does not. Line comments
/// are skipped, so a comment that names a package is not an import.
List<String> exportFindings(String source) {
  final code = source.replaceAll(RegExp(r'//.*$', multiLine: true), '');
  return [
    for (final package in _exportPackages)
      if (code.contains("'package:$package/") ||
          code.contains('"package:$package/'))
        'imports package:$package',
    for (final icon in _exportIcon.allMatches(code)) 'draws ${icon.group(0)}',
  ];
}

bool _importsSharePlus(String source) =>
    exportFindings(source).contains('imports package:share_plus');

String _folderOf(TeamModule module) => 'lib/features/${module.name}';

List<File> _dartFilesUnder(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return const [];
  return [
    for (final entity in dir.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ];
}

void main() {
  group('the scanner', () {
    test('catches a share_plus import and a share control', () {
      const fixture = '''
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

final share = IconButton(icon: const Icon(Icons.share_outlined), onPressed: null);
final save = IconButton(icon: const Icon(Icons.file_download), onPressed: null);
''';
      expect(exportFindings(fixture), [
        'imports package:share_plus',
        'draws Icons.share_outlined',
        'draws Icons.file_download',
      ]);
      expect(_importsSharePlus(fixture), isTrue);
    });

    test('catches print and spreadsheet packages', () {
      expect(exportFindings("import 'package:printing/printing.dart';"),
          ['imports package:printing']);
      expect(exportFindings('import "package:csv/csv.dart";'),
          ['imports package:csv']);
      expect(exportFindings('const i = Icons.print_outlined;'),
          ['draws Icons.print_outlined']);
    });

    test('passes a list with no export and ignores comments', () {
      const fixture = '''
import 'package:flutter/material.dart';

// Never import 'package:share_plus/share_plus.dart' here (#52).
final call = IconButton(icon: const Icon(Icons.call_outlined), onPressed: null);
''';
      expect(exportFindings(fixture), isEmpty);
    });
  });

  group('the app', () {
    test('runs from the app folder, where lib/ is', () {
      expect(Directory('lib/features').existsSync(), isTrue);
      for (final path in _sensitiveFiles) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    });

    test('no sensitive module or sensitive screen imports share_plus', () {
      final files = [
        for (final module in TeamModule.values)
          if (module.sensitive) ..._dartFilesUnder(_folderOf(module)),
        for (final path in _sensitiveFiles) File(path),
      ];
      for (final file in files) {
        expect(_importsSharePlus(file.readAsStringSync()), isFalse,
            reason: file.path);
      }
    });

    test('no module list or sensitive screen shares, downloads or prints', () {
      final files = [
        for (final module in TeamModule.values)
          ..._dartFilesUnder(_folderOf(module)),
        for (final path in _sensitiveFiles) File(path),
      ];
      for (final file in files) {
        expect(exportFindings(file.readAsStringSync()), isEmpty,
            reason: file.path);
      }
    });

    test('share_plus is on the ID card screen only', () {
      final importers = {
        for (final file in _dartFilesUnder('lib'))
          if (_importsSharePlus(file.readAsStringSync()))
            file.path.replaceAll(r'\', '/'),
      };
      expect(importers, _shareAllowed);
    });
  });
}

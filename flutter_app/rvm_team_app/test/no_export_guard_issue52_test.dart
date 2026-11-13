import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// team_app #52, item 10 (and check 8's no-export half): no share, download
/// or print action on any module list, and a test that fails when share_plus
/// is imported under a sensitive module.
///
/// What is scanned comes from the registries, not from folder names: every
/// route the router has under a `TeamModule` prefix, every sensitive route
/// (`isSensitiveLocation`, the class roster included whatever its switch) and
/// every sensitive shell tab is built, and the file that declares its screen
/// is scanned together with the app files it imports
/// (`moduleAndSensitiveScreens`, test/support/source_scan.dart, which the
/// no-copy guard shares). No module route exists yet (#51, #53, #56 and #58
/// add them), so today this pins the class roster, and share_plus staying on
/// the ID card screen alone.

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

/// A share, download or print control drawn as an icon (Material or
/// Cupertino: `CupertinoIcons.share`, `.printer`, `.square_arrow_up`).
final _exportIcon = RegExp(r'Icons\.(share|ios_share|download|file_download|'
    r'cloud_download|print|save_alt|picture_as_pdf|square_arrow_up)\w*');

/// A control named for what it does, e.g. `_ExportButton(` or `ShareTile(`.
final _exportControlName =
    RegExp(r'^_?(Share|Download|Export|Print|Save(As|To))');

/// Words that name an export, inside a control's strings.
final _exportWord = RegExp(
    r'\b(share|download|export|print)(s|ing)?\b|\bsave\s+(as|to)\b',
    caseSensitive: false);

/// A string that is an export label by itself ('Download', 'Export CSV'),
/// wherever it is: a label kept in a constant is still a label.
final _exportLabel = RegExp(
    r'^\s*((share|download|export|print)(s|ing)?\b|save\s+(as|to)\b)',
    caseSensitive: false);

/// Why [source] exports, one line each; empty when it does not: an export
/// package imported, an export icon drawn, a control named for an export, or
/// an export word on a control (a text-only 'Download' button, an 'Export CSV'
/// menu item) or as a label of its own. Comments never count, and a `//`
/// inside a string never hides the code after it.
List<String> exportFindings(String source) {
  final lexed = lex(source);
  final controls = controlsIn(lexed);
  String? innermost(int at) => controlAround(controls, at);

  return [
    for (final package in _exportPackages)
      if (lexed.code.contains("'package:$package/") ||
          lexed.code.contains('"package:$package/'))
        'imports package:$package',
    for (final icon in _exportIcon.allMatches(lexed.masked))
      'draws ${icon.group(0)}',
    for (final c in controls)
      if (_exportControlName.hasMatch(c.name)) 'draws ${c.name}',
    for (final s in lexed.strings)
      if (_exportWord.hasMatch(s.text) && innermost(s.at) != null)
        'labels ${innermost(s.at)} "${s.text}"'
      else if (_exportLabel.hasMatch(s.text) && s.text.length <= 40)
        'labels "${s.text}"',
  ];
}

bool _importsSharePlus(String source) =>
    exportFindings(source).contains('imports package:share_plus');

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

    test('catches the Cupertino share and print icons', () {
      expect(exportFindings('const i = CupertinoIcons.share;'),
          ['draws Icons.share']);
      expect(exportFindings('const i = CupertinoIcons.printer;'),
          ['draws Icons.printer']);
      expect(exportFindings('const i = CupertinoIcons.square_arrow_up;'),
          ['draws Icons.square_arrow_up']);
    });

    test('catches text-only buttons and menu items', () {
      expect(
          exportFindings(
              "final b = TextButton(onPressed: null, child: Text('Download'));"),
          ['labels TextButton "Download"']);
      expect(exportFindings('''
final menu = PopupMenuButton<String>(
  itemBuilder: (_) => const [
    PopupMenuItem<String>(value: 'csv', child: Text('Leads as CSV export')),
    PopupMenuItem(value: 'call', child: Text('Call')),
  ],
);
'''), ['labels PopupMenuItem "Leads as CSV export"']);
      expect(
          exportFindings(
              "final b = FilledButton.icon(onPressed: null, icon: x, label: Text('Share list'));"),
          ['labels FilledButton "Share list"']);
      expect(
          exportFindings(
              "final t = ListTile(title: Text('Print the roster'), onTap: null);"),
          ['labels ListTile "Print the roster"']);
      expect(
          exportFindings(
              'final m = MenuItemButton(onPressed: null, child: Text("Save as PDF"));'),
          ['labels MenuItemButton "Save as PDF"']);
    });

    test('catches a label kept in a constant, and a control named for it', () {
      expect(exportFindings("const _label = 'Export';"), ['labels "Export"']);
      expect(exportFindings('final w = _ExportButton(onTap: null);'),
          ['draws _ExportButton']);
    });

    test('a // or /* inside a string does not hide the code after it', () {
      expect(
          exportFindings(
              "final u = 'https://example.test'; final i = Icons.share;"),
          ['draws Icons.share']);
      expect(exportFindings("final s = '//'; final i = Icons.share;"),
          ['draws Icons.share']);
      expect(exportFindings('final s = "a // b"; final i = Icons.print;'),
          ['draws Icons.print']);
      expect(exportFindings("final s = '/* x'; final i = Icons.share;"),
          ['draws Icons.share']);
      expect(exportFindings("final s = r'C:\\\\x\\\\'; final i = Icons.share;"),
          ['draws Icons.share']);
      expect(
          exportFindings(
              "final s = '\${a ?? '//'} \\' //'; final i = Icons.share;"),
          ['draws Icons.share']);
      expect(
          exportFindings(
              "final s = '''line one\n// still the string\n'''; final i = Icons.share;"),
          ['draws Icons.share']);
    });

    test('passes a list with no export and ignores comments', () {
      const fixture = '''
import 'package:flutter/material.dart';

// Never import 'package:share_plus/share_plus.dart' here (#52).
/* Nor draw Icons.share, /* nested */ or a 'Download' button. */
/// [Icons.print] is not used here.
final call = IconButton(icon: const Icon(Icons.call_outlined), onPressed: null);
final tile = ListTile(title: Text('Shared with HR'), subtitle: Text('Exported on Monday'));
final hint = Text('Ask HR to share the list.');
''';
      expect(exportFindings(fixture), isEmpty);
    });
  });

  group('the app', () {
    test('runs from the app folder, where lib/ is', () {
      expect(Directory('lib/features').existsSync(), isTrue);
      expect(File('lib/router/app_router.dart').existsSync(), isTrue);
    });

    testWidgets('the module and sensitive routes come from the router',
        (tester) async {
      final scanned = await moduleAndSensitiveScreens(tester);

      // Today that is the class roster alone, with its own files.
      expect(scanned.keys, contains('/work/batch/:id/mark'));
      expect(
          scanned['/work/batch/:id/mark'],
          containsAll([
            'lib/features/work/mark_attendance_screen.dart',
            'lib/features/work/bloc/mark_attendance_bloc.dart',
            'lib/widgets/states.dart',
          ]));
      for (final files in scanned.values) {
        expect(files.where(isWiring), isEmpty);
      }
    });

    testWidgets('no sensitive route\'s screen imports share_plus',
        (tester) async {
      final scanned = await sensitiveScreens(tester);
      expect({
        for (final MapEntry(key: path, value: files) in scanned.entries)
          for (final file in files)
            if (_importsSharePlus(File(file).readAsStringSync()))
              '$path: $file',
      }, isEmpty);
    });

    testWidgets(
        'no module list or sensitive screen shares, downloads or prints',
        (tester) async {
      final scanned = await moduleAndSensitiveScreens(tester);
      // Every finding in every file at once, so one run shows them all.
      expect({
        for (final MapEntry(key: path, value: files) in scanned.entries)
          for (final file in files)
            if (exportFindings(File(file).readAsStringSync()) case final found
                when found.isNotEmpty)
              '$path: $file': found,
      }, isEmpty);
    });

    test('share_plus is on the ID card screen only', () {
      final importers = {
        for (final MapEntry(key: file, value: source) in libSources().entries)
          if (_importsSharePlus(source)) file,
      };
      expect(importers, {'lib/features/me/id_card_screen.dart'});
    });
  });
}

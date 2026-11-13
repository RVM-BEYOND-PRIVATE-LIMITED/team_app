import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/router/app_router.dart';
import 'package:rvm_team_app/router/module_routes.dart';
import 'package:rvm_team_app/router/sensitive_routes.dart';
import 'package:rvm_team_app/widgets/secure_scope.dart';

import 'support/app_routes.dart';

/// team_app #52, item 10 (and check 8's no-export half): no share, download
/// or print action on any module list, and a test that fails when share_plus
/// is imported under a sensitive module.
///
/// What is scanned comes from the registries, not from folder names: every
/// route the router has under a [TeamModule] prefix, and every sensitive route
/// ([isSensitiveLocation], the class roster included whatever its switch), is
/// built, and the file that declares its screen is scanned together with the
/// app files it imports. No module route exists yet (#51, #53, #56 and #58 add
/// them), so today this pins the class roster, and share_plus staying on the
/// ID card screen alone.
class _MockTeamAuthBloc extends Mock implements TeamAuthBloc {}

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

/// Something a person taps: a button, a menu item (`PopupMenuItem`,
/// `MenuItemButton`), a chip, a list tile, a tab, or anything wrapped in a tap
/// handler. Its strings are its label, tooltip and the like.
final _control = RegExp(
    r'\b(_?[A-Z]\w*(?:Button|MenuItem|Action|Chip|Tile|Option|Destination)|'
    r'InkWell|InkResponse|GestureDetector|Tab)\b(?:\.\w+)?\s*(?:<[^()]*?>)?\s*\(');

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

/// A Dart source cut into code and strings.
class Lexed {
  Lexed._(this.code, this.masked, this.strings);

  /// The source with every comment blanked (newlines kept, so offsets still
  /// match) and every string as written.
  final String code;

  /// [code] with each string's contents blanked too, so brackets can be
  /// matched and names found without anything inside a string.
  final String masked;

  /// Each string literal's text, with the offset of its opening quote.
  final List<({int at, String text})> strings;
}

/// Cuts [source] into code and strings. A `//` or `/*` inside a string is
/// part of the string, not a comment, and a string inside an interpolation
/// (`'${a ?? 'none'}'`) is a string of its own.
Lexed lex(String source) => _Lexer(source).run();

class _Lexer {
  _Lexer(this._src);

  final String _src;
  final _code = StringBuffer();
  final _masked = StringBuffer();
  final _strings = <({int at, String text})>[];
  var _i = 0;

  Lexed run() {
    _codeUntil(brace: false);
    _strings.sort((a, b) => a.at.compareTo(b.at));
    return Lexed._(_code.toString(), _masked.toString(), _strings);
  }

  void _keep(String c, {bool mask = false}) {
    _code.write(c);
    _masked.write(mask && c != '\n' ? ' ' : c);
  }

  void _blank(String c) {
    final b = c == '\n' ? '\n' : ' ';
    _code.write(b);
    _masked.write(b);
  }

  /// Code to the end, or, inside an interpolation, to its closing brace.
  void _codeUntil({required bool brace}) {
    var depth = 0;
    while (_i < _src.length) {
      final c = _src[_i];
      if (_src.startsWith('//', _i)) {
        while (_i < _src.length && _src[_i] != '\n') {
          _blank(_src[_i++]);
        }
      } else if (_src.startsWith('/*', _i)) {
        _blockComment();
      } else if (c == "'" || c == '"') {
        _string();
      } else {
        if (brace && c == '{') depth++;
        if (brace && c == '}' && depth-- == 0) return;
        _keep(c);
        _i++;
      }
    }
  }

  /// Dart block comments nest.
  void _blockComment() {
    var depth = 0;
    while (_i < _src.length) {
      if (_src.startsWith('/*', _i)) {
        depth++;
        _blank('/');
        _blank('*');
        _i += 2;
      } else if (_src.startsWith('*/', _i)) {
        _blank('*');
        _blank('/');
        _i += 2;
        if (--depth == 0) return;
      } else {
        _blank(_src[_i++]);
      }
    }
  }

  void _string() {
    final at = _i;
    final raw = at > 0 &&
        (_src[at - 1] == 'r' || _src[at - 1] == 'R') &&
        (at < 2 || !RegExp(r'[\w$]').hasMatch(_src[at - 2]));
    final q = _src[at];
    final quote = _src.startsWith(q * 3, at) ? q * 3 : q;
    for (final c in quote.split('')) {
      _keep(c);
    }
    _i += quote.length;
    final text = StringBuffer();
    while (_i < _src.length && !_src.startsWith(quote, _i)) {
      final c = _src[_i];
      if (quote.length == 1 && c == '\n') break; // never closed on its line
      if (!raw && c == r'\' && _i + 1 < _src.length) {
        text.write(_src.substring(_i, _i + 2));
        _keep(c, mask: true);
        _keep(_src[_i + 1], mask: true);
        _i += 2;
      } else if (!raw && _src.startsWith(r'${', _i)) {
        // The expression is code: its strings and comments are lexed as such.
        _keep(r'$', mask: true);
        _keep('{', mask: true);
        _i += 2;
        _codeUntil(brace: true);
        if (_i < _src.length) {
          _keep('}', mask: true);
          _i++;
        }
        text.write(' ');
      } else {
        text.write(c);
        _keep(c, mask: true);
        _i++;
      }
    }
    if (_src.startsWith(quote, _i)) {
      for (final c in quote.split('')) {
        _keep(c);
      }
      _i += quote.length;
    }
    _strings.add((at: at, text: text.toString()));
  }
}

/// The offset of the bracket that closes the one at [open] in [masked].
int _closing(String masked, int open) {
  var depth = 0;
  for (var i = open; i < masked.length; i++) {
    if (masked[i] == '(') {
      depth++;
    } else if (masked[i] == ')' && --depth == 0) {
      return i;
    }
  }
  return masked.length;
}

/// Why [source] exports, one line each; empty when it does not: an export
/// package imported, an export icon drawn, a control named for an export, or
/// an export word on a control (a text-only 'Download' button, an 'Export CSV'
/// menu item) or as a label of its own. Comments never count, and a `//`
/// inside a string never hides the code after it.
List<String> exportFindings(String source) {
  final lexed = lex(source);
  final controls = [
    for (final m in _control.allMatches(lexed.masked))
      (
        name: m.group(1)!,
        open: m.end - 1,
        close: _closing(lexed.masked, m.end - 1)
      ),
  ];
  String? innermost(int at) {
    ({String name, int open, int close})? best;
    for (final c in controls) {
      if (c.open < at && at < c.close && (best == null || c.open > best.open)) {
        best = c;
      }
    }
    return best?.name;
  }

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

List<File> _dartFilesUnder(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return const [];
  return [
    for (final entity in dir.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ];
}

String _slashes(String path) => path.replaceAll(r'\', '/');

/// Every class the app declares, and the file it is declared in.
Map<String, String> _classFiles() {
  final declaration = RegExp(
      r'^(?:(?:abstract|base|final|sealed|interface|mixin)\s+)*class\s+(\w+)',
      multiLine: true);
  return {
    for (final file in _dartFilesUnder('lib'))
      for (final m in declaration.allMatches(lex(file.readAsStringSync()).code))
        m.group(1)!: _slashes(file.path),
  };
}

/// The files that wire the whole app together, and so import every screen.
/// A screen's own imports go through them only for set-up, never for a
/// control, so the walk stops there.
bool _wiring(String path) =>
    path == 'lib/injection.dart' ||
    path == 'lib/main.dart' ||
    path.startsWith('lib/router/');

final _importDirective =
    RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);

/// [file] and every app file it imports, directly or not.
Set<String> _withImports(String file) {
  final seen = <String>{};
  final todo = [file];
  while (todo.isNotEmpty) {
    final path = todo.removeLast();
    if (!seen.add(path) || !File(path).existsSync()) continue;
    final code = lex(File(path).readAsStringSync()).code;
    for (final m in _importDirective.allMatches(code)) {
      final uri = m.group(1)!;
      final String target;
      if (uri.startsWith('package:rvm_team_app/')) {
        target = 'lib/${uri.substring('package:rvm_team_app/'.length)}';
      } else if (uri.contains(':')) {
        continue; // dart: or another package
      } else {
        target = Uri(path: path).resolve(uri).path;
      }
      if (!_wiring(target)) todo.add(target);
    }
  }
  return seen;
}

/// The route paths that need the no-export rule, each with the app files its
/// screen is made of: every route under a module prefix, and every sensitive
/// route (the class roster whatever its switch).
Future<Map<String, Set<String>>> _scannedRoutes(WidgetTester tester) async {
  final auth = _MockTeamAuthBloc();
  when(() => auth.state).thenReturn(const TeamAuthState());
  final router = createRouter(auth);
  addTearDown(router.dispose);
  late BuildContext context;
  await tester.pumpWidget(Builder(builder: (c) {
    context = c;
    return const SizedBox.shrink();
  }));
  final classes = _classFiles();
  return {
    for (final route in builtRoutes(router, context))
      if (moduleForLocation(route.location) != null ||
          isSensitiveLocation(route.location, roster: true))
        route.path: () {
          final built = route.screen;
          final screen = built is SecureScope ? built.child : built;
          final name = '${screen?.runtimeType}'.split('<').first;
          final file = classes[name];
          // A route whose screen cannot be found must not pass unscanned.
          expect(file, isNotNull, reason: '${route.path}: no file for $name');
          return _withImports(file!);
        }(),
  };
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
      final scanned = await _scannedRoutes(tester);

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
        expect(files.where(_wiring), isEmpty);
      }
    });

    testWidgets('no sensitive route\'s screen imports share_plus',
        (tester) async {
      final scanned = await _scannedRoutes(tester);
      expect({
        for (final MapEntry(key: path, value: files) in scanned.entries)
          if (isSensitiveLocation(path.replaceAll(RegExp(r':\w+'), 'x'),
              roster: true))
            for (final file in files)
              if (_importsSharePlus(File(file).readAsStringSync()))
                '$path: $file',
      }, isEmpty);
    });

    testWidgets(
        'no module list or sensitive screen shares, downloads or prints',
        (tester) async {
      final scanned = await _scannedRoutes(tester);
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
        for (final file in _dartFilesUnder('lib'))
          if (_importsSharePlus(file.readAsStringSync())) _slashes(file.path),
      };
      expect(importers, {'lib/features/me/id_card_screen.dart'});
    });
  });
}

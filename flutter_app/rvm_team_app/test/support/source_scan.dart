import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/auth/team_permissions.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/features/shell/tab_registry.dart';
import 'package:rvm_team_app/router/app_router.dart';
import 'package:rvm_team_app/router/module_routes.dart';
import 'package:rvm_team_app/router/sensitive_routes.dart';
import 'package:rvm_team_app/widgets/secure_scope.dart';

import 'app_routes.dart';

// What the source guards share (team_app #52, #54, #55, #58): a Dart lexer
// that tells code from comments and strings, the app's files and the imports
// between them, and the files behind each screen the router or the shell's
// tabs draw. Every guard that scans lib/ for a banned package, widget, label
// or route uses these, so they all agree on what a comment is and on which
// files a screen is made of.

// ── The lexer ───────────────────────────────────────────────────────────────

/// A Dart source cut into code and strings.
class Lexed {
  Lexed._(this.code, this.masked, this.strings);

  /// The source with every comment blanked (newlines kept, so offsets still
  /// match) and every string as written.
  final String code;

  /// [code] with each string's contents blanked too, so brackets can be
  /// matched and names found without anything inside a string. An
  /// interpolation's expression (`${a.b}`) is code, so it stays; a simple one
  /// (`$name`) is part of the string's text.
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

/// The line (from 1) that [offset] of a lexed source is on. The lexer keeps
/// every newline where it was, so an offset into [Lexed.code] or
/// [Lexed.masked] is one into the source too.
int lineOf(String code, int offset) =>
    '\n'.allMatches(code.substring(0, offset)).length + 1;

/// The offset of the bracket that closes the one at [open] in [masked].
int closingBracket(String masked, int open) {
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

/// The lower-case words of a name, a path or a file: 'CampusDrivesTab' gives
/// 'campus drives tab', '/social/new-post' gives 'social new post'.
String nameWords(String s) => s
    .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .replaceAllMapped(RegExp(r'([A-Z])([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

/// A label as lower-case words: 'Add a comment…' gives 'add a comment'.
String labelWords(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// A string that reads as a label: it has a space, or it is one capitalised
/// word ('Approve'). Anything else is a route, a path, an import or a key.
bool isLabel(String text) =>
    text.contains(RegExp(r'\s')) || RegExp(r'^[A-Z][a-z]*$').hasMatch(text);

/// Every name in [lexed]'s code (an identifier, a keyword, a type), with its
/// offset, and the names in each string's simple interpolations (`$count`).
List<({int at, String name})> namesIn(Lexed lexed) {
  final identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');
  return [
    for (final m in identifier.allMatches(lexed.masked))
      (at: m.start, name: m[0]!),
    for (final s in lexed.strings)
      for (final m in RegExp(r'\$([A-Za-z_][A-Za-z0-9_]*)').allMatches(s.text))
        (at: s.at, name: m[1]!),
  ]..sort((a, b) => a.at.compareTo(b.at));
}

// ── Controls ────────────────────────────────────────────────────────────────

/// Something a person taps: a button, a menu item (`PopupMenuItem`,
/// `MenuItemButton`), a chip, a list tile, a tab, or anything wrapped in a tap
/// handler. Its strings are its label, tooltip and the like.
final controlCall = RegExp(
    r'\b(_?[A-Z]\w*(?:Button|MenuItem|Action|Chip|Tile|Option|Destination)|'
    r'InkWell|InkResponse|GestureDetector|Tab)\b(?:\.\w+)?\s*(?:<[^()]*?>)?\s*\(');

/// One control in a source: its name and the brackets around its arguments.
typedef Control = ({String name, int open, int close});

/// Every control [lexed] builds ([controlCall]).
List<Control> controlsIn(Lexed lexed) => [
      for (final m in controlCall.allMatches(lexed.masked))
        (
          name: m.group(1)!,
          open: m.end - 1,
          close: closingBracket(lexed.masked, m.end - 1)
        ),
    ];

/// The name of the innermost of [controls] whose arguments hold offset [at],
/// or null when no control holds it.
String? controlAround(List<Control> controls, int at) {
  Control? best;
  for (final c in controls) {
    if (c.open < at && at < c.close && (best == null || c.open > best.open)) {
      best = c;
    }
  }
  return best?.name;
}

// ── The app's files ─────────────────────────────────────────────────────────

/// Fails at once unless the test runs in the app's own folder (as
/// `flutter test` does), where lib/ is: a scan of nothing would prove nothing.
void requireAppFolder() {
  if (!File('lib/router/app_router.dart').existsSync()) {
    fail('Run this test from flutter_app/rvm_team_app (flutter test does): '
        'it reads lib/ there, and a scan of nothing would prove nothing.');
  }
}

/// [path] with forward slashes, as the guards name files.
String slashes(String path) => path.replaceAll(r'\', '/');

/// Every Dart file under [path], sorted; none when it does not exist.
List<File> dartFilesUnder(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return const [];
  return [
    for (final entity in dir.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
}

/// The app paths of the Dart files under [path] (`lib/features/x/…`).
Set<String> appFilesUnder(String path) {
  requireAppFolder();
  return {for (final f in dartFilesUnder(path)) slashes(f.path)};
}

/// Every Dart file under lib/, by path, with its source.
Map<String, String> libSources() {
  requireAppFolder();
  return {
    for (final f in dartFilesUnder('lib'))
      slashes(f.path): f.readAsStringSync(),
  };
}

/// Every class the app declares, and the file it is declared in.
Map<String, String> classFiles() {
  final declaration = RegExp(
      r'^(?:(?:abstract|base|final|sealed|interface|mixin)\s+)*class\s+(\w+)',
      multiLine: true);
  return {
    for (final MapEntry(key: file, value: source) in libSources().entries)
      for (final m in declaration.allMatches(lex(source).code))
        m.group(1)!: file,
  };
}

/// The files that wire the whole app together, and so import every screen.
/// A screen's own imports go through them only for set-up, never for a
/// control, so a walk stops there. What they draw around every screen (a
/// `SelectionArea` in main.dart's `MaterialApp.router` builder, say) is in
/// no screen's files, so a guard that needs it scans the whole app for it
/// (no_copy_guard_issue52_test.dart).
bool isWiring(String path) =>
    path == 'lib/injection.dart' ||
    path == 'lib/main.dart' ||
    path.startsWith('lib/router/');

/// An `import`, `export` or `part` directive (not `part of`), and its URI.
final _directive = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true);

/// The app files (under lib/) that [source], the file at [path], imports,
/// exports or has as parts. Packages and `dart:` libraries are left out.
Set<String> appImportsOf(String path, String source) {
  const self = 'package:rvm_team_app/';
  final found = <String>{};
  for (final m in _directive.allMatches(lex(source).code)) {
    final uri = m.group(1)!;
    if (uri.startsWith(self)) {
      found.add('lib/${uri.substring(self.length)}');
    } else if (!uri.contains(':')) {
      found.add(Uri(path: path).resolve(uri).path); // a relative import
    }
  }
  return found;
}

/// Every file under lib/, with the app files it imports directly.
Map<String, Set<String>> importGraph() => {
      for (final MapEntry(key: file, value: source) in libSources().entries)
        file: appImportsOf(file, source),
    };

/// [file] and every app file it imports, directly or not, stopping at the
/// wiring files ([isWiring]).
Set<String> withImports(String file) {
  final seen = <String>{};
  final todo = [file];
  while (todo.isNotEmpty) {
    final path = todo.removeLast();
    if (!seen.add(path) || !File(path).existsSync()) continue;
    for (final target in appImportsOf(path, File(path).readAsStringSync())) {
      if (!isWiring(target)) todo.add(target);
    }
  }
  return seen;
}

/// The files that belong to a module: [seeds] (its folder and its screens'
/// files), and every file they import that nothing outside the module
/// imports, as far as that goes: its blocs, repositories, data sources and
/// models, wherever they live. A file another part of the app imports too
/// is shared (the team kit, the ESS models), not the module's own, and stays
/// out. The wiring files ([isWiring]) import everything, so they do not count
/// as importers. [graph] is [importGraph] unless a self-test passes its own.
Set<String> moduleOwnedFiles(Set<String> seeds,
    {Map<String, Set<String>>? graph}) {
  final imports = graph ?? importGraph();
  final importers = <String, Set<String>>{};
  for (final MapEntry(key: file, value: targets) in imports.entries) {
    if (isWiring(file)) continue;
    for (final target in targets) {
      (importers[target] ??= {}).add(file);
    }
  }
  final owned = {...seeds};
  for (var grew = true; grew;) {
    grew = false;
    for (final file in [...owned]) {
      for (final target in imports[file] ?? const <String>{}) {
        if (owned.contains(target) || isWiring(target)) continue;
        if ((importers[target] ?? const {}).every(owned.contains)) {
          grew = owned.add(target) || grew;
        }
      }
    }
  }
  return owned;
}

// ── The screens ─────────────────────────────────────────────────────────────

class _MockTeamAuthBloc extends Mock implements TeamAuthBloc {}

/// Every route of the app's router ([createRouter]), each built at a
/// location that matches it.
Future<List<BuiltRoute>> appRoutes(WidgetTester tester) async {
  requireAppFolder();
  final auth = _MockTeamAuthBloc();
  when(() => auth.state).thenReturn(const TeamAuthState());
  final router = createRouter(auth);
  addTearDown(router.dispose);
  late BuildContext context;
  await tester.pumpWidget(Builder(builder: (c) {
    context = c;
    return const SizedBox.shrink();
  }));
  return builtRoutes(router, context);
}

/// The file that declares [screen]'s class. [what] names the route or tab in
/// the failure: a screen whose file cannot be found must not pass unscanned.
String screenFile(Widget? screen, Map<String, String> classes, String what) {
  final shown = screen is SecureScope ? screen.child : screen;
  final name = '${shown?.runtimeType}'.split('<').first;
  final file = classes[name];
  expect(file, isNotNull, reason: '$what: no file for $name');
  return file!;
}

/// The paths of the router's routes whose location [include] picks, each
/// with the file that declares its screen.
Future<Map<String, String>> routeScreenFiles(
    WidgetTester tester, bool Function(String location) include) async {
  final routes = await appRoutes(tester);
  final classes = classFiles();
  return {
    for (final route in routes)
      if (include(route.location))
        route.path: screenFile(route.screen, classes, route.path),
  };
}

/// Every shell tab marked sensitive ([TeamTab.sensitive]) for any role or
/// kind of sign-in, as `tab <id>`, with the file that declares its body.
Map<String, String> sensitiveTabFiles() {
  final classes = classFiles();
  return {
    for (final role in AppRole.values)
      for (final attendance in [false, true])
        for (final spec in teamTabRegistry)
          if (spec.tab(TeamViewer(role: role, attendance: attendance))
              case final tab when tab.sensitive)
            'tab ${tab.id}': screenFile(tab.body, classes, 'tab ${tab.id}'),
  };
}

/// The sensitive screens, each with the app files it is made of (its file and
/// [withImports]): every route [isSensitiveLocation] marks (every route of a
/// sensitive [TeamModule], and the class roster whatever its switch), and
/// every sensitive shell tab. Each is keyed by its route path, or `tab <id>`.
Future<Map<String, Set<String>>> sensitiveScreens(WidgetTester tester) async {
  final routes = await routeScreenFiles(
      tester, (location) => isSensitiveLocation(location, roster: true));
  return {
    for (final MapEntry(key: path, value: file) in routes.entries)
      path: withImports(file),
    for (final MapEntry(key: tab, value: file) in sensitiveTabFiles().entries)
      tab: withImports(file),
  };
}

/// [sensitiveScreens], and every other route under a [TeamModule] prefix:
/// what the no-export rule covers (team_app #52 item 10).
Future<Map<String, Set<String>>> moduleAndSensitiveScreens(
    WidgetTester tester) async {
  final routes = await routeScreenFiles(
      tester,
      (location) =>
          moduleForLocation(location) != null ||
          isSensitiveLocation(location, roster: true));
  return {
    for (final MapEntry(key: path, value: file) in routes.entries)
      path: withImports(file),
    for (final MapEntry(key: tab, value: file) in sensitiveTabFiles().entries)
      tab: withImports(file),
  };
}

/// The routes at or under the prefixes of [modules], each with the file that
/// declares its screen.
Future<Map<String, String>> moduleRouteFiles(
        WidgetTester tester, Set<TeamModule> modules) =>
    routeScreenFiles(
        tester, (location) => modules.contains(moduleForLocation(location)));

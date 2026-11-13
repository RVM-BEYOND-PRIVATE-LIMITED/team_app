import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/router/module_routes.dart';

import 'support/source_scan.dart';

/// team_app #55, check "no screen has an input for a scorecard number": the
/// app shows scorecards and never edits them. Targets are set only on the
/// Scheduler web (Scheduler_frontend#105).
///
/// What is scanned comes from the registries (test/support/source_scan.dart):
/// every Dart file under lib/features/scorecards/, the file that declares the
/// screen of each route at or under `TeamModule.scorecards` (`/scorecards`),
/// and every file they import that no other part of the app imports
/// (`moduleOwnedFiles`). Comments and strings never count. It fails on:
/// * an input: TextField, TextFormField, CupertinoTextField,
///   CupertinoTextFormFieldRow, EditableText, Slider, RangeSlider,
///   CupertinoSlider, DropdownButtonFormField, `Form(` or `keyboardType:`;
/// * a POST, PUT or PATCH from a scorecards data source: those files, and any
///   file under lib/ named for scorecards (a data source the HoO and CEO
///   screens share is still one), by a dio call (`.post(`, `.put(`,
///   `.patch(`) or a request whose `method:` is one of them.
///
/// Today lib/features/scorecards/ holds the state badge alone, with no
/// input and no request, and no /scorecards route exists. The check is ticked
/// once the screens exist and this still passes.
void main() {
  group('the guard catches', () {
    test('every kind of input', () {
      expect(_inputs('final f = TextField(controller: target);'),
          ['TextField on line 1']);
      expect(_inputs('''
final f = TextFormField(
  keyboardType: TextInputType.number,
);'''), ['TextFormField on line 1', 'keyboardType: on line 2']);
      expect(_inputs('final f = CupertinoTextField(placeholder: x);'),
          ['CupertinoTextField on line 1']);
      expect(_inputs('final f = CupertinoTextFormFieldRow(prefix: x);'),
          ['CupertinoTextFormFieldRow on line 1']);
      expect(_inputs('final f = EditableText(controller: c, focusNode: n);'),
          ['EditableText on line 1']);
      expect(_inputs('final s = Slider(value: 1, onChanged: null);'),
          ['Slider on line 1']);
      expect(_inputs('final s = Slider.adaptive(value: 1, onChanged: null);'),
          ['Slider on line 1']);
      expect(_inputs('final s = RangeSlider(values: r, onChanged: null);'),
          ['RangeSlider on line 1']);
      expect(_inputs('final s = CupertinoSlider(value: 1, onChanged: null);'),
          ['CupertinoSlider on line 1']);
      expect(
          _inputs(
              'final d = DropdownButtonFormField<int>(items: const [], onChanged: null);'),
          ['DropdownButtonFormField on line 1']);
      expect(_inputs('final f = Form(key: _key, child: fields);'),
          ['Form( on line 1']);
    });

    test('a POST, PUT or PATCH', () {
      expect(
          _writes("Future<void> f() => _dio.post('/scorecards/targets', "
              "data: {'target_paise': 100});"),
          ['POST on line 1']);
      expect(_writes("final r = _dio.put<Map<String, dynamic>>('/x/1');"),
          ['PUT on line 1']);
      expect(_writes("final r = _dio.patch('/x/1', data: body);"),
          ['PATCH on line 1']);
      expect(_writes('''
final r = _dio.request<void>('/x/1',
    options: Options(method: 'patch'));'''), ['PATCH on line 2']);
      expect(_writes("final r = _dio.postUri(Uri.parse('/x'));"),
          ['POST on line 1']);
    });
  });

  group('the guard allows', () {
    test('a read-only scorecard', () {
      const source = '''
import 'package:flutter/material.dart';

// No TextField, Slider or Form( here: targets are set on the Scheduler web.
/* _dio.post('/scorecards/targets') /* nested */ never */
final badge = ScoreStateBadge(state: parseScoreState(json['state']));
final money = Text(RvmMoney.fromPaise(row.actualPaise));
final hint = Text('Targets are set on the Scheduler web. Form (web only).');
final key = GlobalKey<FormState>();
final read = _dio.get('/scorecards/me', options: TeamModule.scorecards.requestOptions);
final sliderTheme = SliderTheme.of(context);
const method = 'POST is never sent from here';
''';
      expect(_inputs(source), isEmpty);
      expect(_writes(source), isEmpty);
    });
  });

  group('the app', () {
    test('the scan reads the scorecards folder', () {
      requireAppFolder();
      // An empty or wrong folder must fail here, not pass the guard below.
      expect(
          appFilesUnder('lib/features/scorecards'),
          containsAll([
            'lib/features/scorecards/score_state.dart',
            'lib/features/scorecards/score_state_badge.dart',
          ]));
      expect(TeamModule.scorecards.routePrefix, '/scorecards');
    });

    testWidgets('no scorecards screen has an input, and nothing writes',
        (tester) async {
      final routes = await moduleRouteFiles(tester, {TeamModule.scorecards});
      final own = moduleOwnedFiles({
        ...appFilesUnder('lib/features/scorecards'),
        ...routes.values,
      });
      final named = {
        for (final file in libSources().keys)
          if (file.contains('scorecard')) file,
      };
      String read(String file) => File(file).readAsStringSync();
      final found = [
        for (final file in own)
          for (final input in _inputs(read(file))) '$file: $input',
        for (final file in {...own, ...named})
          for (final write in _writes(read(file))) '$file: $write',
      ];
      expect(
        found,
        isEmpty,
        reason: 'team_app#55: no screen has an input for a scorecard '
            'number, and the app never writes a scorecard or a target '
            '(they are edited on the Scheduler web, Scheduler_frontend#105). '
            'Found:\n  ${found.join('\n  ')}',
      );
    });
  });
}

/// An input widget, by name (Material and Cupertino).
final _inputWidget = RegExp(r'\b(TextField|TextFormField|CupertinoTextField|'
    r'CupertinoTextFormFieldRow|EditableText|Slider|RangeSlider|'
    r'CupertinoSlider|DropdownButtonFormField)\b');

/// A form, which only exists to collect input.
final _form = RegExp(r'\bForm\s*(?:<[^()]*?>)?\s*\(');

/// A keyboard asked for, which only a field does.
final _keyboard = RegExp(r'\bkeyboardType\s*:');

/// Each input in [source], as 'Widget on line n'. Comments and strings never
/// count.
List<String> _inputs(String source) {
  final lexed = lex(source);
  final found = <({int at, String what})>[
    for (final m in _inputWidget.allMatches(lexed.masked))
      (at: m.start, what: m[1]!),
    for (final m in _form.allMatches(lexed.masked))
      (at: m.start, what: 'Form('),
    for (final m in _keyboard.allMatches(lexed.masked))
      (at: m.start, what: 'keyboardType:'),
  ]..sort((a, b) => a.at.compareTo(b.at));
  return [
    for (final f in found) '${f.what} on line ${lineOf(lexed.code, f.at)}',
  ];
}

/// A dio write: `.post(`, `.put(`, `.patch(`, their `…Uri(` forms, with or
/// without type arguments.
final _writeCall = RegExp(r'\.(post|put|patch)(?:Uri)?\s*(?:<[^()]*?>)?\s*\(');

/// A request whose method is a write.
final _writeMethod = RegExp(r'''\bmethod\s*:\s*['"](post|put|patch)['"]''',
    caseSensitive: false);

/// Each POST, PUT or PATCH [source] sends, as 'POST on line n'.
List<String> _writes(String source) {
  final lexed = lex(source);
  final found = <({int at, String method})>[
    for (final m in _writeCall.allMatches(lexed.masked))
      (at: m.start, method: m[1]!.toUpperCase()),
    for (final m in _writeMethod.allMatches(lexed.code))
      (at: m.start, method: m[1]!.toUpperCase()),
  ]..sort((a, b) => a.at.compareTo(b.at));
  return [
    for (final f in found) '${f.method} on line ${lineOf(lexed.code, f.at)}',
  ];
}

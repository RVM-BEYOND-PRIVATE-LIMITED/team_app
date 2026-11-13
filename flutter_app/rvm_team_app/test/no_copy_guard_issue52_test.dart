import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/features/inbox/inbox_screen.dart';
import 'package:rvm_team_app/features/shell/tab_registry.dart';

import 'support/source_scan.dart';

/// team_app #52, item 9 (the guard half): no show-number or copy-number
/// action and no text selection on a sensitive list. The masked value itself
/// (a number the app never receives in full) is the servers' half.
///
/// What is scanned is what the no-export guard scans, through the same
/// registries (`sensitiveScreens`, test/support/source_scan.dart): every
/// route of a module marked sensitive (`TeamModule.sensitive`: CRM, fees,
/// desk, placement, complaints), the class roster whatever its
/// `SECURE_ROSTER` switch, and every sensitive shell tab, each with the file
/// that declares its screen and the app files it imports. The scan fails on:
/// * the clipboard (`Clipboard.setData`, `ClipboardData`);
/// * selectable text (`SelectableText`, `SelectionArea`, `SelectableRegion`),
///   a field with `enableInteractiveSelection: true`, and a read-only
///   `TextField`, `TextFormField` or `CupertinoTextField` that does not say
///   `enableInteractiveSelection: false` (Flutter lets a read-only field's
///   text be selected and copied unless it does);
/// * a copy, show-number, reveal or unmask control: its icon (copy, eye), its
///   name (`_CopyButton`, `RevealNumberTile`), or those words on its label or
///   tooltip ('Copy number', 'Show full number', 'Reveal', 'Unmask'), or as a
///   label of their own.
///
/// A screen's imports stop at the files that sit above every screen (main.dart
/// and its `MaterialApp.router` builder, the router, the shell, the widgets
/// they wrap a screen in), so a `SelectionArea` or `SelectableRegion` there,
/// which makes every screen under it selectable, the class roster included,
/// is not in any screen's files. So those two are banned in the whole of lib/
/// and in the workspace packages (flutter_app/packages/*/lib), except in the
/// files [_selectionRegionAllowed] names, with why: none today.
///
/// And in the whole of lib/: a `tel:` URI built anywhere but
/// lib/platform/call_launcher.dart, the one place that may hold a number long
/// enough to hand it to the dialer (team_app #50 item 1): a `tel:` string, or
/// the scheme `'tel'` itself, even held in a constant
/// (`const _scheme = 'tel'`).
///
/// No module screen exists yet, so today this pins the class roster.

/// A copy or reveal control drawn as an icon (Material or Cupertino:
/// `CupertinoIcons.doc_on_clipboard`, `.eye`).
final _copyIcon = RegExp(r'Icons\.(copy|content_copy|copy_all|file_copy|'
    r'doc_on_clipboard|doc_on_doc|visibility|remove_red_eye|eye)\w*');

/// A control named for what it does, e.g. `_CopyButton(` or `RevealTile(`.
final _copyControlName =
    RegExp(r'^_?(Copy|Reveal|Unmask|(Show|View)(Full)?(Number|Phone|Mobile))');

/// 'Copy', 'Copied', 'Reveal', 'Unmask', and 'Show number', 'Show the full
/// phone number', 'View mobile'.
const _copyWords = r'(cop(y|ies|ied|ying)\b|reveal\w*|unmask\w*|'
    r'(show|view|see|display)\s+'
    r'((the|full|whole|complete|phone|mobile|contact)\s+)*'
    r'(numbers?|phones?|mobiles?)\b)';

/// Those words inside a control's strings.
final _copyWord = RegExp('\\b$_copyWords', caseSensitive: false);

/// A string that is a copy or reveal label by itself ('Copy', 'Copied to
/// clipboard', 'Show number'), wherever it is: a label kept in a constant is
/// still a label.
final _copyLabel = RegExp('^\\s*$_copyWords', caseSensitive: false);

final _clipboard = RegExp(r'\bClipboard\w*');
final _selectable =
    RegExp(r'\b(SelectableText|SelectionArea|SelectableRegion)\b');
final _selectionOn = RegExp(r'\benableInteractiveSelection\s*:\s*true\b');

/// A text field, Material or Cupertino. Its `enableInteractiveSelection` is
/// on unless it is obscured, so a read-only one holding a value lets it be
/// selected and copied.
final _textField = RegExp(r'\b(TextField|TextFormField|CupertinoTextField|'
    r'CupertinoTextFormFieldRow)\b(?:\.\w+)?\s*\(');
final _readOnly = RegExp(r'\breadOnly\s*:\s*true\b');
final _selectionOff = RegExp(r'\benableInteractiveSelection\s*:\s*false\b');

/// Why [source] lets a sensitive value out by copy, selection or reveal, one
/// line each; empty when it does not. Comments never count.
List<String> copyFindings(String source) {
  final lexed = lex(source);
  final controls = controlsIn(lexed);
  return [
    for (final m in _clipboard.allMatches(lexed.masked)) 'uses ${m.group(0)}',
    for (final m in _selectable.allMatches(lexed.masked)) 'draws ${m.group(0)}',
    for (final _ in _selectionOn.allMatches(lexed.masked))
      'enableInteractiveSelection: true',
    for (final m in _textField.allMatches(lexed.masked))
      if (lexed.masked
              .substring(m.end - 1, closingBracket(lexed.masked, m.end - 1))
          case final args
          when _readOnly.hasMatch(args) && !_selectionOff.hasMatch(args))
        'read-only ${m.group(1)} with selection on',
    for (final icon in _copyIcon.allMatches(lexed.masked))
      'draws ${icon.group(0)}',
    for (final c in controls)
      if (_copyControlName.hasMatch(c.name)) 'draws ${c.name}',
    for (final s in lexed.strings)
      if (_copyWord.hasMatch(s.text) && controlAround(controls, s.at) != null)
        'labels ${controlAround(controls, s.at)} "${s.text}"'
      else if (_copyLabel.hasMatch(s.text) && s.text.length <= 40)
        'labels "${s.text}"',
  ];
}

/// Region-wide selection: everything drawn under one can be selected and
/// copied. Where it sits decides which screens it opens, not what a screen
/// imports, so it is checked in every file.
final _selectionRegion = RegExp(r'\b(SelectionArea|SelectableRegion)\b');

/// The files that may draw a [_selectionRegion], each with why. Only a leaf
/// screen that no sensitive screen is drawn under may (a route pushed on top
/// of it is its sibling in the navigator, not its child), and the per-screen
/// scan still fails it if a sensitive screen imports it. Never main.dart, the
/// router, the shell or a shared widget: every screen sits under them. None
/// today (the ID card's link is one `SelectableText`, which selects only
/// itself).
const _selectionRegionAllowed = <String, String>{};

/// Each [_selectionRegion] in [sources] (path to source) outside [allowed],
/// as 'path:line draws SelectionArea'. Comments never count.
List<String> selectionRegionFindings(Map<String, String> sources,
    {Map<String, String> allowed = _selectionRegionAllowed}) {
  final found = <String>[];
  for (final MapEntry(key: file, value: source) in sources.entries) {
    if (allowed.containsKey(file)) continue;
    final lexed = lex(source);
    for (final m in _selectionRegion.allMatches(lexed.masked)) {
      found.add('$file:${lineOf(lexed.code, m.start)} draws ${m.group(0)}');
    }
  }
  return found;
}

/// Every Dart file under the workspace packages' lib/ folders
/// (flutter_app/packages/*/lib), by path from flutter_app
/// (`packages/core_ui/lib/…`), with its source. The app's `MaterialApp`
/// builder or shell could wrap every screen in one of their widgets.
Map<String, String> workspacePackageSources() {
  requireAppFolder();
  final packages = Directory('../packages');
  if (!packages.existsSync()) return const {};
  final folders = [
    for (final entity in packages.listSync())
      if (entity is Directory) slashes(entity.path),
  ]..sort();
  return {
    for (final folder in folders)
      for (final f in dartFilesUnder('$folder/lib'))
        slashes(f.path).replaceFirst('../', ''): f.readAsStringSync(),
  };
}

/// The one file that may build a `tel:` URI.
const _callLauncher = 'lib/platform/call_launcher.dart';

final _telText = RegExp(r'^\s*tel:', caseSensitive: false);

/// Each `tel:` URI [source] builds ('tel:$n'), and each `'tel'` string, the
/// scheme itself (`Uri(scheme: 'tel', …)`, or a constant holding it that a
/// `Uri(scheme: _scheme)` uses), or none when [file] is [_callLauncher].
List<String> telFindings(String source, {required String file}) {
  if (file == _callLauncher) return const [];
  final lexed = lex(source);
  return [
    for (final s in lexed.strings)
      if (_telText.hasMatch(s.text))
        'builds a tel: URI on line ${lineOf(lexed.code, s.at)}'
      else if (s.text.trim().toLowerCase() == 'tel')
        'names the tel: scheme on line ${lineOf(lexed.code, s.at)}',
  ];
}

void main() {
  group('the guard catches', () {
    test('the clipboard', () {
      expect(
          copyFindings(
              'Future<void> f() => Clipboard.setData(ClipboardData(text: phone));'),
          ['uses Clipboard', 'uses ClipboardData']);
    });

    test('selectable text', () {
      expect(copyFindings('final t = SelectableText(lead.name);'),
          ['draws SelectableText']);
      expect(copyFindings('final a = SelectionArea(child: list);'),
          ['draws SelectionArea']);
      expect(
          copyFindings(
              'final f = TextField(readOnly: true, enableInteractiveSelection: true);'),
          [
            'enableInteractiveSelection: true',
            'read-only TextField with selection on',
          ]);
    });

    test('a read-only field, which Flutter lets be selected by default', () {
      expect(
          copyFindings('final f = TextField(readOnly: true, '
              'controller: TextEditingController(text: s.fullName));'),
          ['read-only TextField with selection on']);
      expect(copyFindings('''
final f = TextFormField(
  initialValue: lead.phone,
  readOnly: true,
);'''), ['read-only TextFormField with selection on']);
      expect(
          copyFindings(
              'final f = CupertinoTextField.borderless(readOnly: true);'),
          ['read-only CupertinoTextField with selection on']);
    });

    test('a selection region above the screens, in a wiring or shared file',
        () {
      // A SelectionArea in main.dart's MaterialApp.router builder, a router
      // or shell builder, or a widget they wrap every screen in makes every
      // screen selectable, though no screen imports it.
      expect(
          selectionRegionFindings({
            'lib/main.dart': '''
final app = MaterialApp.router(
  builder: (context, child) => EnvRibbon(
    environment: env,
    child: SelectionArea(child: VersionGate(child: child!)),
  ),
);
''',
            'lib/router/app_router.dart': '''
final shell = ShellRoute(
    builder: (_, __, child) => SelectableRegion(
        focusNode: node, selectionControls: controls, child: child));
''',
            'lib/features/shell/team_shell.dart':
                'Widget body() => SelectionArea(child: tabs[_index].body);',
            'packages/core_ui/lib/src/page.dart':
                'Widget page(Widget c) => SelectionArea(child: c);',
          }),
          [
            'lib/main.dart:4 draws SelectionArea',
            'lib/router/app_router.dart:2 draws SelectableRegion',
            'lib/features/shell/team_shell.dart:1 draws SelectionArea',
            'packages/core_ui/lib/src/page.dart:1 draws SelectionArea',
          ]);
    });

    test('copy and reveal icons', () {
      expect(
          copyFindings(
              'final b = IconButton(icon: const Icon(Icons.copy_rounded), onPressed: null);'),
          ['draws Icons.copy_rounded']);
      expect(copyFindings('const i = Icons.content_copy_outlined;'),
          ['draws Icons.content_copy_outlined']);
      expect(copyFindings('const i = Icons.visibility_outlined;'),
          ['draws Icons.visibility_outlined']);
      expect(copyFindings('const i = CupertinoIcons.doc_on_clipboard;'),
          ['draws Icons.doc_on_clipboard']);
      expect(
          copyFindings('const i = CupertinoIcons.eye;'), ['draws Icons.eye']);
    });

    test('copy, show-number, reveal and unmask labels on controls', () {
      expect(
          copyFindings(
              "final b = TextButton(onPressed: null, child: Text('Copy number'));"),
          ['labels TextButton "Copy number"']);
      expect(copyFindings('''
final menu = PopupMenuButton<String>(
  itemBuilder: (_) => const [
    PopupMenuItem<String>(value: 'show', child: Text('Show full number')),
    PopupMenuItem(value: 'call', child: Text('Call')),
  ],
);
'''), ['labels PopupMenuItem "Show full number"']);
      expect(
          copyFindings(
              "final b = IconButton(tooltip: 'Tap to reveal the phone', icon: x, onPressed: null);"),
          ['labels IconButton "Tap to reveal the phone"']);
      expect(
          copyFindings(
              "final t = ListTile(title: Text('Unmask mobile'), onTap: null);"),
          ['labels ListTile "Unmask mobile"']);
      expect(
          copyFindings(
              'final c = ActionChip(label: Text("View the phone number"), onPressed: null);'),
          ['labels ActionChip "View the phone number"']);
    });

    test('a label kept in a constant, and a control named for it', () {
      expect(copyFindings("const _label = 'Copy';"), ['labels "Copy"']);
      expect(copyFindings("const _toast = 'Copied to clipboard';"),
          ['labels "Copied to clipboard"']);
      expect(copyFindings("const _label = 'Show number';"),
          ['labels "Show number"']);
      expect(copyFindings('final w = _CopyNumberButton(onTap: null);'),
          ['draws _CopyNumberButton']);
      expect(copyFindings('final w = RevealTile(lead: lead);'),
          ['draws RevealTile']);
      expect(copyFindings('final w = ShowFullNumberAction(lead: lead);'),
          ['draws ShowFullNumberAction']);
    });

    test('a tel: URI built outside the call helper', () {
      const file = 'lib/features/crm/lead_screen.dart';
      expect(telFindings(r"final u = Uri.parse('tel:$phone');", file: file),
          ['builds a tel: URI on line 1']);
      expect(
          telFindings("final u = Uri(scheme: 'tel', path: phone);", file: file),
          ['names the tel: scheme on line 1']);
      expect(telFindings('\nfinal u = Uri.parse("TEL:" + phone);', file: file),
          ['builds a tel: URI on line 2']);
    });

    test('the tel scheme held in a constant', () {
      expect(
          telFindings(
              "const _telScheme = 'tel';\n"
              'final u = Uri(scheme: _telScheme, path: n);',
              file: 'lib/features/crm/lead_screen.dart'),
          ['names the tel: scheme on line 1']);
      expect(
          telFindings("const scheme = 'TEL';",
              file: 'lib/features/desk/desk_screen.dart'),
          ['names the tel: scheme on line 1']);
    });
  });

  group('the guard allows', () {
    test('a roster or lead list that only shows and calls', () {
      const fixture = '''
import 'package:flutter/material.dart';

// Never Clipboard.setData or SelectableText here (#52 item 9).
/* No 'Copy number' or 'Show number' button, /* nested */ no Icons.copy. */
/// [Icons.visibility] is not used here.
final style = theme.textTheme.bodySmall?.copyWith(fontSize: 12);
final tile = CheckboxListTile(
  value: true,
  onChanged: null,
  title: Text(student.fullName ?? 'Student'),
  subtitle: Text('Admission number 1234'),
);
final call = IconButton(
    tooltip: 'Call', icon: const Icon(Icons.call_outlined), onPressed: null);
final more = TextButton(onPressed: null, child: Text('Show more'));
const done = 'Phone app opened.';
const hint = 'The number stays hidden. Ask the student desk for changes.';
''';
      expect(copyFindings(fixture), isEmpty);
    });

    test('a field the person types in, and selection switched off', () {
      expect(copyFindings('''
final reason = TextField(
    controller: _reason,
    decoration: const InputDecoration(labelText: 'Reason for absence'));
final note = TextField(enableInteractiveSelection: false);
final shown = TextField(
    readOnly: true,
    enableInteractiveSelection: false,
    controller: TextEditingController(text: s.fullName));
final editable = TextField(readOnly: false, controller: _reason);
'''), isEmpty);
    });

    test('a selection region in an allowed screen, or in a comment', () {
      const idCard = 'lib/features/me/id_card_screen.dart';
      const source = 'Widget build(_) => SelectionArea(child: card);';
      expect(selectionRegionFindings({idCard: source}), hasLength(1));
      expect(
          selectionRegionFindings({idCard: source},
              allowed: {idCard: 'the ID card only, a leaf screen'}),
          isEmpty);
      expect(
          selectionRegionFindings({
            'lib/main.dart': '// Never a SelectionArea above the screens.\n'
                '/// [SelectableRegion] neither.\n'
                'final off = SelectionContainer.disabled(child: child);',
          }),
          isEmpty);
    });

    test('a tel: URI in the call helper, and tel: in a comment', () {
      const source = r'''
/// Hands `tel:<number>` to the dialer.
final u = Uri(scheme: 'tel', path: number);
''';
      expect(telFindings(source, file: 'lib/platform/call_launcher.dart'),
          isEmpty);
      expect(
          telFindings(
              '// tel: links stay in the call helper.\n'
              "const label = 'Hotel: Pune'; const hint = 'Tel no. hidden';\n"
              "const kind = 'telephone';",
              file: 'lib/features/crm/lead_screen.dart'),
          isEmpty);
    });
  });

  group('the app', () {
    test('runs from the app folder, where lib/ is', () {
      requireAppFolder();
      expect(libSources().length, greaterThan(50));
    });

    testWidgets('the sensitive screens come from the router and the tabs',
        (tester) async {
      final scanned = await sensitiveScreens(tester);

      // Today that is the class roster alone, with its own files.
      expect(scanned.keys, ['/work/batch/:id/mark']);
      expect(
          scanned['/work/batch/:id/mark'],
          containsAll([
            'lib/features/work/mark_attendance_screen.dart',
            'lib/features/work/bloc/mark_attendance_bloc.dart',
            'lib/widgets/team_kit.dart',
          ]));
      for (final files in scanned.values) {
        expect(files.where(isWiring), isEmpty);
      }
    });

    testWidgets("a sensitive tab's body is scanned with its imports",
        (tester) async {
      // A sensitive tab stands in for a future dialer or desk tab.
      final saved = [...teamTabRegistry];
      addTearDown(() => teamTabRegistry
        ..clear()
        ..addAll(saved));
      teamTabRegistry.add(TeamTabSpec(
        id: 'dialer',
        visible: (_) => true,
        tab: (_) => const TeamTab(
            id: 'dialer',
            label: 'Dialer',
            icon: Icons.dialpad_outlined,
            selectedIcon: Icons.dialpad_rounded,
            body: InboxScreen(),
            sensitive: true),
      ));

      final scanned = await sensitiveScreens(tester);
      expect(scanned.keys, containsAll(['/work/batch/:id/mark', 'tab dialer']));
      expect(scanned['tab dialer'],
          contains('lib/features/inbox/inbox_screen.dart'));
      expect(scanned['tab dialer'], contains('lib/widgets/team_kit.dart'));
    });

    testWidgets('no sensitive screen copies, selects or reveals',
        (tester) async {
      final scanned = await sensitiveScreens(tester);
      // Every finding in every file at once, so one run shows them all.
      expect({
        for (final MapEntry(key: path, value: files) in scanned.entries)
          for (final file in files)
            if (copyFindings(File(file).readAsStringSync()) case final found
                when found.isNotEmpty)
              '$path: $file': found,
      }, isEmpty,
          reason: 'team_app #52 item 9: a sensitive list shows a masked value '
              'and never copies, selects or reveals it.');
    });

    testWidgets(
        "today's copy actions are found, and none is on a sensitive screen",
        (tester) async {
      final sensitive = {
        for (final files in (await sensitiveScreens(tester)).values) ...files,
      };
      final copying = {
        for (final MapEntry(key: file, value: source) in libSources().entries)
          if (copyFindings(source).isNotEmpty) file,
      };
      // The scanner sees real code: the document and ID card screens copy a
      // link, and the ID card shows it as selectable text.
      expect(
          copying,
          containsAll([
            'lib/features/hr/hr_documents_screen.dart',
            'lib/features/me/documents_screen.dart',
            'lib/features/me/id_card_screen.dart',
          ]));
      expect(copying.intersection(sensitive), isEmpty);
    });

    test('no selection region sits above the screens', () {
      final sources = {...libSources(), ...workspacePackageSources()};
      // The files above every screen are read, and so are the packages: a
      // scan of nothing would prove nothing.
      expect(sources.keys,
          containsAll(['lib/main.dart', 'lib/router/app_router.dart']));
      expect(sources.keys.where((f) => f.startsWith('lib/features/shell/')),
          isNotEmpty);
      expect(sources.keys.where((f) => f.startsWith('packages/core_ui/lib/')),
          isNotEmpty);
      expect(selectionRegionFindings(sources), isEmpty,
          reason: 'team_app #52 item 9: a SelectionArea or SelectableRegion '
              'makes every screen drawn under it selectable, the class '
              'roster included, whatever that screen imports.');
      for (final file in _selectionRegionAllowed.keys) {
        expect(sources.keys, contains(file), reason: 'stale entry: $file');
        expect(
            isWiring(file) ||
                file.startsWith('lib/features/shell/') ||
                file.startsWith('lib/widgets/') ||
                file.startsWith('packages/'),
            isFalse,
            reason: '$file sits above other screens: it cannot be allowed');
      }
    });

    test('only the call helper builds a tel: URI', () {
      final sources = libSources();
      expect({
        for (final MapEntry(key: file, value: source) in sources.entries)
          if (telFindings(source, file: file) case final found
              when found.isNotEmpty)
            file: found,
      }, isEmpty,
          reason: 'A tel: URI holds the number. Only $_callLauncher builds '
              'one, from the number a module server hands it.');
      // The helper itself does, so the rule would see one anywhere else.
      expect(telFindings(sources[_callLauncher]!, file: 'lib/elsewhere.dart'),
          hasLength(1));
    });
  });
}

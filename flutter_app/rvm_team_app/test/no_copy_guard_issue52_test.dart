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
/// * selectable text (`SelectableText`, `SelectionArea`, `SelectableRegion`)
///   and a field with `enableInteractiveSelection: true`;
/// * a copy, show-number, reveal or unmask control: its icon (copy, eye), its
///   name (`_CopyButton`, `RevealNumberTile`), or those words on its label or
///   tooltip ('Copy number', 'Show full number', 'Reveal', 'Unmask'), or as a
///   label of their own.
///
/// And in the whole of lib/: a `tel:` URI built anywhere but
/// lib/platform/call_launcher.dart, the one place that may hold a number long
/// enough to hand it to the dialer (team_app #50 item 1).
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

/// The one file that may build a `tel:` URI.
const _callLauncher = 'lib/platform/call_launcher.dart';

final _telText = RegExp(r'^\s*tel:', caseSensitive: false);
final _schemeArgument = RegExp(r'scheme\s*:\s*$');

/// Each `tel:` URI [source] builds ('tel:$n', `Uri(scheme: 'tel', …)`), or
/// none when [file] is [_callLauncher].
List<String> telFindings(String source, {required String file}) {
  if (file == _callLauncher) return const [];
  final lexed = lex(source);
  return [
    for (final s in lexed.strings)
      if (_telText.hasMatch(s.text) ||
          (s.text.trim().toLowerCase() == 'tel' &&
              _schemeArgument.hasMatch(
                  lexed.masked.substring(s.at < 40 ? 0 : s.at - 40, s.at))))
        'builds a tel: URI on line ${lineOf(lexed.code, s.at)}',
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
          ['enableInteractiveSelection: true']);
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
          ['builds a tel: URI on line 1']);
      expect(telFindings('\nfinal u = Uri.parse("TEL:" + phone);', file: file),
          ['builds a tel: URI on line 2']);
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
'''), isEmpty);
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
              "const kind = 'tel'; const label = 'Hotel: Pune';",
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

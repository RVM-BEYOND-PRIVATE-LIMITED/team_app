import 'dart:io';

import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/features/fees/outcome/followup_outcome.dart';
import 'package:rvm_team_app/features/fees/outcome/outcome_rules.dart';
import 'package:rvm_team_app/features/fees/outcome/outcome_sheet.dart';
import 'package:rvm_team_app/widgets/team_kit.dart';

/// team_app #53, work 12a: the rules of the fees follow-up outcome form (8a).
///
/// The rules are the Scheduler's own: utils/followUpFallback.js refuses a next
/// follow-up date on or before IST today with the message below and allows no
/// date; controllers/batchAllotmentController.js has the two outcome words.
/// No endpoint is called or mocked: the save waits for Scheduler_Backend#176.

/// utils/followUpFallback.js:76, copied so a change on either side fails here.
const _schedulerMessage =
    'The next follow-up date must be after today. Pick tomorrow or a later date.';

final _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// 15:30 IST on Friday 13 Nov 2026.
final _midday = DateTime.utc(2026, 11, 13, 10);

/// A rupee sign, "Rs" before a figure, INR or the word rupee.
final _money = RegExp(r'₹|\bRs\.?\s*\d|\bINR\b|rupee', caseSensitive: false);

/// An `import`, `export` or `part` directive at the start of a line, up to its
/// `;` (a conditional import names more than one URI). `part of` names the
/// library the file belongs to, not one it uses, so it is left out.
final _directive = RegExp(
    r'''^[ \t]*(?:import|export|part)\b(?![ \t]+of\b)([^;]*);''',
    multiLine: true);

/// A quoted URI, in single or double quotes.
final _quoted = RegExp(r'''['"]([^'"]+)['"]''');

/// Every URI that [source] imports, exports or includes as a part, in order.
List<String> _directiveUris(String source) => [
      for (final d in _directive.allMatches(source))
        for (final q in _quoted.allMatches(d[1]!)) q[1]!,
    ];

/// Names that would mean the form is wired to a save, a route or the wire.
final _wiring = RegExp(
    r'fromJson|toJson|jsonEncode|jsonDecode|\bDio\b|GoRoute|getIt|'
    r'FollowUpTask|FollowUpsRemoteDataSource|RemoteDataSource|Repository');

/// A money field: no rupees on this form.
final _moneyField = RegExp(r'₹|paise|amount|rupee', caseSensitive: false);

/// What the sheets opened from the test screen handed back, in order.
class _Opened {
  final results = <FollowupOutcomeDraft?>[];
}

/// A screen with an "Open" button that opens the outcome sheet: through
/// [showFollowupOutcomeSheet], or, with [onSave], as a sheet that stays open
/// and hands each Save to [onSave].
Future<_Opened> _open(
  WidgetTester tester, {
  DateTime Function()? clock,
  bool dark = false,
  ValueChanged<FollowupOutcomeDraft>? onSave,
}) async {
  final opened = _Opened();
  final now = clock ?? () => _midday;
  await tester.pumpWidget(MaterialApp(
    theme: dark
        ? RvmTheme.dark(seed: RvmColors.clay)
        : RvmTheme.light(seed: RvmColors.clay),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              if (onSave != null) {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      FollowupOutcomeSheet(clock: now, onSave: onSave),
                );
                return;
              }
              opened.results
                  .add(await showFollowupOutcomeSheet(context, clock: now));
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return opened;
}

Finder get _save => find.ancestor(
    of: find.text('Save'),
    matching: find.byWidgetPredicate((w) => w is FilledButton));

Finder get _dateButton => find.byWidgetPredicate((w) => w is OutlinedButton);

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(_save).enabled;

Future<void> _tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) =>
    _tapOn(tester, find.text(text));

/// Opens the calendar from the date field, taps [day] when given, and OK.
Future<void> _pickDay(WidgetTester tester, {String? day}) async {
  await _tapOn(tester, _dateButton);
  if (day != null) {
    await tester.tap(find.text(day));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Every piece of text drawn on screen, typed text included.
List<String> _drawn(WidgetTester tester) => [
      for (final e in find.byType(RichText, skipOffstage: false).evaluate())
        (e.widget as RichText).text.toPlainText(),
      for (final e in find.byType(EditableText, skipOffstage: false).evaluate())
        (e.widget as EditableText).controller.text,
    ];

void main() {
  group('the next-date rule (utils/followUpFallback.js)', () {
    test('the refusal is the Scheduler\'s, word for word', () {
      expect(nextFollowUpDateRefused, _schedulerMessage);
    });

    test('IST today comes from the UTC clock', () {
      expect(istToday(DateTime.utc(2026, 11, 13, 18, 29)),
          DateTime(2026, 11, 13));
      expect(istToday(DateTime.utc(2026, 11, 13, 18, 30)),
          DateTime(2026, 11, 14));
      // 00:00Z is 05:30 IST on the same day.
      expect(istToday(DateTime.utc(2026, 11, 13)), DateTime(2026, 11, 13));
      // IST reaches the new year at 18:30Z on 31 Dec.
      expect(istToday(DateTime.utc(2026, 12, 31, 18, 30)), DateTime(2027));
      expect(istTomorrow(DateTime.utc(2026, 12, 31, 18, 29)), DateTime(2027));
      expect(istTomorrow(DateTime.utc(2026, 11, 13, 18, 30)),
          DateTime(2026, 11, 15));
      // A timestamp with an offset, as a server writes it, is its instant.
      expect(istToday(DateTime.parse('2026-11-14T00:00:00+05:30')),
          DateTime(2026, 11, 14));
      expect(istToday(DateTime.parse('2026-11-13T23:59:00+05:30')),
          DateTime(2026, 11, 13));
      expect(istToday(DateTime.parse('2026-11-13T13:00:00-05:00')),
          DateTime(2026, 11, 13));
      expect(istToday(DateTime.parse('2026-11-13T13:00:00-05:30')),
          DateTime(2026, 11, 14));
    });

    // Dart has no DateTime in a fixed zone other than UTC: a local one is in
    // the machine's zone, so this only tests something off UTC. On a UTC
    // machine it is skipped, and says so, rather than passing for nothing.
    final machineOnUtc = DateTime(2026, 11, 13).timeZoneOffset == Duration.zero;
    test('a local time is read as the same instant', () {
      for (final instant in [
        DateTime.utc(2026, 11, 13, 18, 29),
        DateTime.utc(2026, 11, 13, 18, 30),
        DateTime.utc(2026, 11, 13, 1),
        DateTime.utc(2026, 11, 13, 13),
        DateTime.utc(2026, 11, 13, 22),
      ]) {
        final local = instant.toLocal();
        expect(local.isUtc, isFalse);
        expect(istToday(local), istToday(instant), reason: '$local');
        expect(istTomorrow(local), istTomorrow(instant), reason: '$local');
      }
    },
        skip: machineOnUtc
            ? 'the machine is on UTC; run with TZ=Asia/Kolkata or '
                'TZ=America/New_York to test it'
            : false);

    test('IST today and earlier are refused; tomorrow and no date pass', () {
      for (final refused in [
        DateTime(2026, 11, 13),
        DateTime(2026, 11, 12),
        DateTime(2025, 12, 31),
      ]) {
        expect(validateNextFollowUpDate(refused, nowUtc: _midday),
            _schedulerMessage,
            reason: '$refused');
      }
      for (final allowed in [DateTime(2026, 11, 14), DateTime(2027)]) {
        expect(validateNextFollowUpDate(allowed, nowUtc: _midday), isNull,
            reason: '$allowed');
      }
      expect(validateNextFollowUpDate(null, nowUtc: _midday), isNull);
    });

    test('at 18:29Z (23:59 IST on the 13th) the 13th is refused and the '
        '14th passes', () {
      final now = DateTime.utc(2026, 11, 13, 18, 29);
      expect(validateNextFollowUpDate(DateTime(2026, 11, 13), nowUtc: now),
          _schedulerMessage);
      expect(validateNextFollowUpDate(DateTime(2026, 11, 14), nowUtc: now),
          isNull);
    });

    test('at 18:30Z (00:00 IST on the 14th) the 14th is refused', () {
      final now = DateTime.utc(2026, 11, 13, 18, 30);
      expect(validateNextFollowUpDate(DateTime(2026, 11, 14), nowUtc: now),
          _schedulerMessage);
      expect(validateNextFollowUpDate(DateTime(2026, 11, 15), nowUtc: now),
          isNull);
    });

    test('only the day of the date counts, as in the Scheduler\'s YYYY-MM-DD',
        () {
      expect(
          validateNextFollowUpDate(DateTime(2026, 11, 13, 23, 59),
              nowUtc: _midday),
          _schedulerMessage);
      expect(
          validateNextFollowUpDate(DateTime(2026, 11, 14, 0, 1),
              nowUtc: _midday),
          isNull);
      expect(validateNextFollowUpDate(DateTime.utc(2026, 11, 14), nowUtc: _midday),
          isNull);
    });

    test('the outcomes are two of the Scheduler\'s follow-up words', () {
      expect([for (final o in FollowupOutcome.values) o.label],
          ['Answered', 'No Answer']);
    });
  });

  group('the outcome sheet', () {
    testWidgets('reads Answered and No Answer, a remark and a next date',
        (tester) async {
      await _open(tester);
      for (final label in [
        'Call outcome',
        'OUTCOME',
        'Answered',
        'No Answer',
        'REMARK (OPTIONAL)',
        'NEXT FOLLOW-UP (OPTIONAL)',
        'Pick a date',
        'Tomorrow or later.',
        'Save',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      // A checked state in a mutually exclusive group, as Flutter's Radio:
      // Android reads a radio button, checked or not checked.
      final semantics = tester.ensureSemantics();
      for (final label in ['Answered', 'No Answer']) {
        expect(
            tester.getSemantics(find.text(label)),
            containsSemantics(
              label: label,
              isButton: true,
              hasCheckedState: true,
              isChecked: false,
              isSelected: false,
              isInMutuallyExclusiveGroup: true,
              hasTapAction: true,
            ),
            reason: '$label before a choice');
      }
      await _tapText(tester, 'No Answer');
      expect(
          tester.getSemantics(find.text('No Answer')),
          containsSemantics(
            label: 'No Answer',
            isButton: true,
            hasCheckedState: true,
            isChecked: true,
            isSelected: false,
            isInMutuallyExclusiveGroup: true,
          ));
      expect(
          tester.getSemantics(find.text('Answered')),
          containsSemantics(
            label: 'Answered',
            hasCheckedState: true,
            isChecked: false,
            isInMutuallyExclusiveGroup: true,
          ));
      semantics.dispose();
    });

    testWidgets('Save stays off until an outcome is chosen', (tester) async {
      final opened = await _open(tester);
      expect(_saveEnabled(tester), isFalse);
      expect(find.text('Choose Answered or No Answer to save.'), findsOneWidget);

      // A remark and a date alone do not turn it on.
      await tester.enterText(find.byType(TextField), 'Busy, call later');
      await _pickDay(tester);
      expect(_saveEnabled(tester), isFalse);
      await _tapText(tester, 'Save');
      expect(opened.results, isEmpty);
      expect(find.byType(FollowupOutcomeSheet), findsOneWidget);

      await _tapText(tester, 'Answered');
      expect(_saveEnabled(tester), isTrue);
      expect(find.text('Choose Answered or No Answer to save.'), findsNothing);
    });

    testWidgets('the calendar\'s first day is IST tomorrow', (tester) async {
      await _open(tester);
      await _tapOn(tester, _dateButton);
      final picker =
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.firstDate, DateTime(2026, 11, 14));
      expect(picker.initialDate, DateTime(2026, 11, 14));
      expect(picker.currentDate, DateTime(2026, 11, 13), reason: 'IST today');

      // Today is drawn but cannot be picked.
      await tester.tap(find.text('13'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nov 14, 2026'), findsOneWidget);
    });

    for (final (clock, first, today) in [
      (DateTime.utc(2026, 11, 13, 18, 29), 14, 13),
      (DateTime.utc(2026, 11, 13, 18, 30), 15, 14),
    ]) {
      testWidgets('at ${clock.toIso8601String()} the first day is the $first',
          (tester) async {
        await _open(tester, clock: () => clock);
        await _tapOn(tester, _dateButton);
        final picker =
            tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
        expect(picker.firstDate, DateTime(2026, 11, first));
        expect(picker.currentDate, DateTime(2026, 11, today));
      });
    }

    testWidgets('Save hands back the outcome, the trimmed remark and the day',
        (tester) async {
      final opened = await _open(tester);
      await _tapText(tester, 'No Answer');
      await tester.enterText(
          find.byType(TextField), '  Switched off, try in the evening  ');
      await _pickDay(tester, day: '20');
      expect(find.textContaining('Nov 20, 2026'), findsOneWidget);

      await _tapText(tester, 'Save');
      expect(find.byType(FollowupOutcomeSheet), findsNothing);
      final draft = opened.results.single!;
      expect(draft.outcome, FollowupOutcome.noAnswer);
      expect(draft.remark, 'Switched off, try in the evening');
      expect(draft.nextDate, DateTime(2026, 11, 20));
      expect(draft.idempotencyKey, matches(_uuidV4));
    });

    testWidgets('no remark and no date are allowed; a date can be cleared',
        (tester) async {
      final opened = await _open(tester);
      await _tapText(tester, 'Answered');
      await _pickDay(tester);
      expect(find.text('Pick a date'), findsNothing);
      await _tapOn(tester, find.byTooltip('Clear date'));
      expect(find.text('Pick a date'), findsOneWidget);
      expect(find.byTooltip('Clear date'), findsNothing);

      await _tapText(tester, 'Save');
      final draft = opened.results.single!;
      expect(draft.outcome, FollowupOutcome.answered);
      expect(draft.remark, '');
      expect(draft.nextDate, isNull);
    });

    testWidgets('a day that became today at midnight is refused with the '
        'Scheduler\'s words', (tester) async {
      var now = DateTime.utc(2026, 11, 13, 18, 29);
      final opened = await _open(tester, clock: () => now);
      await _tapText(tester, 'Answered');
      await _pickDay(tester); // 14 Nov: tomorrow at 23:59 IST.

      now = DateTime.utc(2026, 11, 13, 18, 31); // 00:01 IST on the 14th.
      await _tapText(tester, 'Save');
      expect(find.text(_schedulerMessage), findsOneWidget);
      expect(find.byType(FollowupOutcomeSheet), findsOneWidget);
      expect(opened.results, isEmpty);

      await _pickDay(tester); // The calendar now starts at the 15th.
      expect(find.text(_schedulerMessage), findsNothing);
      await _tapText(tester, 'Save');
      expect(opened.results.single!.nextDate, DateTime(2026, 11, 15));
    });

    testWidgets('two Saves on one sheet carry one key', (tester) async {
      final drafts = <FollowupOutcomeDraft>[];
      await _open(tester, onSave: drafts.add);
      await _tapText(tester, 'Answered');
      await _tapText(tester, 'Save');
      await _tapText(tester, 'Save');

      expect(drafts, hasLength(2));
      expect(drafts.first.idempotencyKey, matches(_uuidV4));
      expect(drafts.last.idempotencyKey, drafts.first.idempotencyKey);
      expect(find.byType(FollowupOutcomeSheet), findsOneWidget,
          reason: 'the sheet stays open for a retry');
    });

    testWidgets('a second Save before the sheet is gone closes it once',
        (tester) async {
      // Flutter drops a second touch in the frame after a pop by itself; a
      // screen reader's activate reaches the button all the same.
      final semantics = tester.ensureSemantics();
      final opened = await _open(tester);
      await _tapText(tester, 'Answered');
      tester.semantics.tap(find.semantics.byLabel('Save'));
      tester.semantics.tap(find.semantics.byLabel('Save'));
      await tester.pumpAndSettle();
      semantics.dispose();

      expect(opened.results, hasLength(1));
      expect(opened.results.single!.idempotencyKey, matches(_uuidV4));
      expect(find.text('Open'), findsOneWidget,
          reason: 'the screen under the sheet stays');
    });

    testWidgets('a new sheet makes a new key', (tester) async {
      final opened = await _open(tester);
      await _tapText(tester, 'Answered');
      await _tapText(tester, 'Save');
      await _tapText(tester, 'Open');
      await _tapText(tester, 'Answered');
      await _tapText(tester, 'Save');

      expect(opened.results, hasLength(2));
      final keys = {for (final d in opened.results) d!.idempotencyKey};
      expect(keys, hasLength(2));
      for (final key in keys) {
        expect(key, matches(_uuidV4));
      }
    });

    testWidgets('closing without saving hands back nothing', (tester) async {
      final opened = await _open(tester);
      await _tapText(tester, 'Answered');
      await _tapOn(tester, find.byTooltip('Close'));
      expect(find.byType(FollowupOutcomeSheet), findsNothing);
      expect(opened.results, [null]);
    });

    testWidgets('draws no rupee sign or figure in rupees', (tester) async {
      var now = _midday;
      await _open(tester, clock: () => now);
      void noMoney(String when) {
        final drawn = _drawn(tester);
        expect(drawn, contains('Answered'), reason: when);
        expect(drawn.where(_money.hasMatch), isEmpty, reason: when);
      }

      noMoney('opened');
      await _tapText(tester, 'Answered');
      await _pickDay(tester, day: '14');
      noMoney('filled in');
      now = DateTime.utc(2026, 11, 13, 18, 31);
      await _tapText(tester, 'Save');
      expect(find.text(_schedulerMessage), findsOneWidget);
      noMoney('date refused');
    });

    test('is not wired: no route, data source, JSON or money field', () {
      final files = Directory('lib/features/fees/outcome')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files.map((f) => f.uri.pathSegments.last),
          containsAll(['outcome_sheet.dart', 'outcome_rules.dart']));
      const allowed = {
        'package:core_network/core_network.dart', // IdempotencyInterceptor
        'package:core_ui/core_ui.dart',
        '../../../widgets/team_kit.dart',
        'followup_outcome.dart',
        'outcome_rules.dart',
      };
      final seen = <String>{};
      for (final file in files) {
        final source = file.readAsStringSync();
        for (final uri in _directiveUris(source)) {
          seen.add(uri);
          expect(uri.startsWith('package:flutter/') || allowed.contains(uri),
              isTrue,
              reason: '${file.path} imports, exports or parts $uri');
        }
        expect(_wiring.hasMatch(source), isFalse, reason: file.path);
        expect(_moneyField.hasMatch(source), isFalse, reason: file.path);
      }
      // The directives were read at all.
      expect(seen,
          containsAll(['package:flutter/material.dart', 'outcome_rules.dart']));
    });

    test('the not-wired guard reads every directive form', () {
      // Each of these must be caught; the old guard missed the double-quoted
      // import, the export and the part.
      expect(
          _directiveUris('''
import "package:dio/dio.dart";
import 'package:core_ui/core_ui.dart' show RvmSpacing;
export 'package:go_router/go_router.dart';
part "outcome_wire.dart";
part of 'outcome_sheet.dart';
import 'package:flutter/material.dart'
    if (dart.library.io) 'package:get_it/get_it.dart';
/// import 'package:not_a_directive/x.dart';
'''),
          [
            'package:dio/dio.dart',
            'package:core_ui/core_ui.dart',
            'package:go_router/go_router.dart',
            'outcome_wire.dart',
            'package:flutter/material.dart',
            'package:get_it/get_it.dart',
          ]);
      expect(_wiring.hasMatch('final d = Dio();'), isTrue);
      expect(_moneyField.hasMatch('const amount = 1;'), isTrue);
    });
  });

  group('fits every screen', () {
    for (final size in const [Size(320, 568), Size(800, 1280)]) {
      for (final scale in const [1.0, 2.0, 3.0]) {
        for (final dark in const [false, true]) {
          for (final keyboard in const [false, true]) {
            testWidgets(
                '${size.width.toInt()}x${size.height.toInt()} at text '
                'x${scale.toInt()}${dark ? ', dark' : ''}'
                '${keyboard ? ', keyboard open' : ''}', (tester) async {
              // The calendar is Flutter's own and not under test: the day is
              // picked on a tablet at text x1, then the sheet is laid out at
              // the size and text scale under test.
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = const Size(800, 1280);
              addTearDown(tester.view.reset);
              addTearDown(
                  tester.platformDispatcher.clearTextScaleFactorTestValue);
              final opened = await _open(tester, dark: dark);
              await _pickDay(tester, day: '20');

              tester.view.physicalSize = size;
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: 'no outcome yet');
              expect(
                  MediaQuery.textScalerOf(tester.element(find.text('Save')))
                      .scale(10),
                  10 * scale);

              // The keyboard takes the bottom 45% of the screen.
              final keyboardHeight = keyboard ? size.height * 0.45 : 0.0;
              if (keyboard) {
                await _tapOn(tester, find.byType(TextField));
                await tester.enterText(find.byType(TextField),
                    'Asked for a call back on Monday after lunch');
                tester.view.viewInsets =
                    FakeViewPadding(bottom: keyboardHeight);
                await tester.pumpAndSettle();
                expect(tester.testTextInput.isVisible, isTrue);
                expect(tester.takeException(), isNull, reason: 'keyboard up');
              }

              await _tapText(tester, 'No Answer');
              expect(tester.takeException(), isNull, reason: 'outcome chosen');

              final answered = find.ancestor(
                  of: find.text('Answered'), matching: find.byType(TeamCard));
              final noAnswer = find.ancestor(
                  of: find.text('No Answer'), matching: find.byType(TeamCard));

              // Side by side only on the tablet below text x3; one above the
              // other on a narrow phone or with large text.
              final sideBySide = size.width >= 800 && scale < 3;
              final a = tester.getRect(answered);
              final b = tester.getRect(noAnswer);
              if (sideBySide) {
                expect(b.top, a.top, reason: 'side by side');
                expect(b.left, greaterThan(a.right), reason: 'side by side');
              } else {
                expect(b.top, greaterThan(a.bottom), reason: 'stacked');
                expect(b.left, a.left, reason: 'stacked');
                expect(b.width, a.width, reason: 'stacked');
              }

              // Every control can be scrolled to where it can be seen: above
              // the keyboard when it is open, inside the screen's width, and
              // at least 44 px tall. The remark field is left out: at 320x568
              // and text x3 it is taller than the space above the keyboard,
              // and it scrolls itself to keep the caret in view.
              final visibleBottom = size.height - keyboardHeight;
              for (final (name, control) in [
                ('Answered', answered),
                ('No Answer', noAnswer),
                ('date', _dateButton),
                ('clear date', find.byTooltip('Clear date')),
                ('close', find.byTooltip('Close')),
                ('Save', _save),
              ]) {
                await tester.ensureVisible(control);
                await tester.pumpAndSettle();
                final rect = tester.getRect(control);
                expect(rect.height, greaterThanOrEqualTo(44), reason: name);
                expect(rect.left, greaterThanOrEqualTo(0), reason: name);
                expect(rect.right, lessThanOrEqualTo(size.width),
                    reason: name);
                expect(rect.top, greaterThanOrEqualTo(0), reason: name);
                expect(rect.bottom, lessThanOrEqualTo(visibleBottom),
                    reason: '$name is above the keyboard');
              }

              await tester.tap(find.text('Save'));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final draft = opened.results.single!;
              expect(draft.outcome, FollowupOutcome.noAnswer);
              expect(draft.nextDate, DateTime(2026, 11, 20));
            });
          }
        }
      }
    }
  });
}

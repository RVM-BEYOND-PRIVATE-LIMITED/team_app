import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/features/scorecards/score_state.dart';
import 'package:rvm_team_app/features/scorecards/score_state_badge.dart';
import 'package:rvm_team_app/widgets/team_kit.dart';

/// Issue #55, item 6: a scorecard number's `state` from the server (`green`,
/// `red` or `none`; Scheduler_Backend#177, item 11) shows as color + icon +
/// word, and `none` shows no color. No screen uses the badge yet: the
/// scorecard screens wait for the scorecard API (Scheduler_Backend#177).

/// The green and red colors. A `none` badge paints none of them.
final _signalColors = <Color>{
  RvmColors.success,
  RvmColors.successSoft,
  RvmColors.danger,
  RvmColors.dangerSoft,
};

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
}) =>
    tester.pumpWidget(MaterialApp(
      theme: RvmTheme.light(seed: RvmColors.clay),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    ));

TeamPill _pill(WidgetTester tester) => tester.widget<TeamPill>(find.descendant(
      of: find.byType(ScoreStateBadge),
      matching: find.byType(TeamPill),
    ));

/// Every color the badge paints: the icon, the word, the pill's fill and its
/// border.
Set<Color> _paintedColors(WidgetTester tester) {
  final colors = <Color>{};
  final inBadge = find.descendant(
    of: find.byType(ScoreStateBadge),
    matching: find.byWidgetPredicate((_) => true),
  );
  for (final widget in tester.widgetList(inBadge)) {
    if (widget is Icon && widget.color != null) colors.add(widget.color!);
    if (widget is Text && widget.style?.color != null) {
      colors.add(widget.style!.color!);
    }
    if (widget is Container && widget.decoration is BoxDecoration) {
      final box = widget.decoration! as BoxDecoration;
      if (box.color != null) colors.add(box.color!);
      final border = box.border;
      if (border is Border) {
        colors.addAll([
          border.top.color,
          border.right.color,
          border.bottom.color,
          border.left.color,
        ]);
      }
    }
  }
  return colors;
}

void main() {
  group('parseScoreState', () {
    test('reads the three states the server sends', () {
      expect(parseScoreState('green'), ScoreState.green);
      expect(parseScoreState('red'), ScoreState.red);
      expect(parseScoreState('none'), ScoreState.none);
    });

    test('ignores case and spaces, like the other wire parsers', () {
      expect(parseScoreState(' Green '), ScoreState.green);
      expect(parseScoreState('RED'), ScoreState.red);
      expect(parseScoreState('None'), ScoreState.none);
    });

    test('anything else is none, so it never shows a color', () {
      for (final raw in <Object?>[
        null,
        '',
        '   ',
        'amber',
        'grey',
        'greenish',
        'on_target',
        1,
        true,
        const ['green'],
        const {'state': 'red'},
      ]) {
        expect(parseScoreState(raw), ScoreState.none, reason: '$raw');
      }
    });
  });

  group('ScoreStateBadge', () {
    testWidgets('green: the success pill, a tick and "On target"',
        (tester) async {
      await _pump(tester, const ScoreStateBadge(state: ScoreState.green));

      expect(_pill(tester).tone, TeamPillTone.success);
      expect(find.text('On target'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      final colors = _paintedColors(tester);
      expect(colors, containsAll([RvmColors.success, RvmColors.successSoft]));
      expect(colors, isNot(contains(RvmColors.danger)));
      expect(colors, isNot(contains(RvmColors.dangerSoft)));
    });

    testWidgets('red: the danger pill, an alert icon and "Off target"',
        (tester) async {
      await _pump(tester, const ScoreStateBadge(state: ScoreState.red));

      expect(_pill(tester).tone, TeamPillTone.danger);
      expect(find.text('Off target'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      final colors = _paintedColors(tester);
      expect(colors, containsAll([RvmColors.danger, RvmColors.dangerSoft]));
      expect(colors, isNot(contains(RvmColors.success)));
      expect(colors, isNot(contains(RvmColors.successSoft)));
    });

    testWidgets('none: no color, a neutral pill with "No target"',
        (tester) async {
      await _pump(tester, const ScoreStateBadge(state: ScoreState.none));

      expect(_pill(tester).tone, TeamPillTone.neutral);
      expect(find.text('No target'), findsOneWidget);
      final colors = _paintedColors(tester);
      expect(colors.intersection(_signalColors), isEmpty);
      // The look of every other neutral pill: white, muted text, hairline.
      expect(colors,
          containsAll([RvmColors.white, RvmColors.muted, RvmColors.line]));
    });

    testWidgets('an unknown server state shows no color', (tester) async {
      await _pump(tester, ScoreStateBadge(state: parseScoreState('amber')));

      expect(find.text('No target'), findsOneWidget);
      expect(_paintedColors(tester).intersection(_signalColors), isEmpty);
    });

    testWidgets('each state has its own word and icon, not only a color',
        (tester) async {
      final words = <String>{};
      final icons = <IconData>{};
      for (final state in ScoreState.values) {
        await _pump(tester, ScoreStateBadge(state: state));
        final pill = _pill(tester);
        expect(pill.label.trim(), isNotEmpty, reason: '$state');
        expect(pill.icon, isNotNull, reason: '$state');
        words.add(pill.label);
        icons.add(pill.icon!);
      }
      expect(words, hasLength(ScoreState.values.length));
      expect(icons, hasLength(ScoreState.values.length));
    });

    testWidgets('a screen reader hears the word', (tester) async {
      final semantics = tester.ensureSemantics();
      for (final (state, word) in [
        (ScoreState.green, 'On target'),
        (ScoreState.red, 'Off target'),
        (ScoreState.none, 'No target'),
      ]) {
        await _pump(tester, ScoreStateBadge(state: state));
        expect(find.bySemanticsLabel(word), findsOneWidget, reason: '$state');
      }
      semantics.dispose();
    });

    testWidgets('dense gives the smaller pill', (tester) async {
      await _pump(
          tester, const ScoreStateBadge(state: ScoreState.red, dense: true));
      expect(_pill(tester).dense, isTrue);

      await _pump(tester, const ScoreStateBadge(state: ScoreState.red));
      expect(_pill(tester).dense, isFalse);
    });

    testWidgets('with room to spare the pill keeps its normal size',
        (tester) async {
      await _pump(
        tester,
        const TeamPill(
          label: 'On target',
          tone: TeamPillTone.success,
          icon: Icons.check_circle_rounded,
        ),
      );
      final normal = tester.getRect(find.byType(TeamPill)).size;

      await _pump(tester, const ScoreStateBadge(state: ScoreState.green));
      expect(tester.getRect(find.byType(TeamPill)).size, normal);
    });

    testWidgets(
        'a narrow column at twice the text size: no overflow, the word whole',
        (tester) async {
      const column = 56.0;
      for (final state in ScoreState.values) {
        await _pump(
          tester,
          SizedBox(width: column, child: ScoreStateBadge(state: state)),
          textScale: 2,
        );

        expect(tester.takeException(), isNull, reason: '$state');
        expect(tester.getSize(find.byType(ScoreStateBadge)).width,
            lessThanOrEqualTo(column));
        // Drawn scaled down inside the column, never past its edge.
        expect(tester.getRect(find.byType(TeamPill)).width,
            lessThanOrEqualTo(column + 0.001));
        expect(find.text(_pill(tester).label), findsOneWidget);
      }
    });
  });
}

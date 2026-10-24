import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/widgets/team_kit.dart';

/// Regression tests for issues_image/issue14: a OnePlus 12R in system dark
/// mode showed black input fields on a white card with washed-out text, while
/// light-mode devices looked normal. The app is locked to the light palette
/// (main.dart: ThemeMode.light), and shared surfaces resolve from the theme
/// instead of hardcoded light colors.
void main() {
  testWidgets('dark system brightness still resolves the light palette',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });

    Color? cardColor;
    Color? fillColor;
    await tester.pumpWidget(
      MaterialApp(
        theme: RvmTheme.light(seed: RvmColors.clay),
        themeMode: ThemeMode.light,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              cardColor = Theme.of(context).cardColor;
              fillColor = Theme.of(context)
                  .inputDecorationTheme
                  .fillColor;
              return const TeamCard(child: Text('x'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Light palette wins even though the device reports dark mode, and the
    // shared card + input surfaces resolve from that same theme.
    final theme = RvmTheme.light(seed: RvmColors.clay);
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.light);
    expect(cardColor, theme.cardColor);
    expect(fillColor, theme.inputDecorationTheme.fillColor);
  });

  testWidgets('TeamCard follows the theme card color in both modes',
      (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: brightness == Brightness.light
              ? RvmTheme.light(seed: RvmColors.clay)
              : RvmTheme.dark(seed: RvmColors.clay),
          home: const Scaffold(body: TeamCard(child: Text('x'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(TeamCard));
      final material =
          tester.widget<Material>(find.descendant(
        of: find.byType(TeamCard),
        matching: find.byType(Material),
      ).first);
      expect(material.color, Theme.of(context).cardColor);
    }
  });
}

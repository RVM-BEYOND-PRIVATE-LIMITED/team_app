import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/features/me/appearance_sheet.dart';
import 'package:rvm_team_app/theme/theme_cubit.dart';
import 'package:rvm_team_app/theme/theme_local_store.dart';
import 'package:rvm_team_app/theme/theme_preference.dart';
import 'package:rvm_team_app/theme/theme_preferences_repository.dart';
import 'package:rvm_team_app/widgets/team_kit.dart';

class _MockRepo extends Mock implements ThemePreferencesRepository {}

class _MockStore extends Mock implements ThemeLocalStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(ThemeChoice.light);
    registerFallbackValue(
        const ThemePreference(choice: ThemeChoice.light, open: true));
  });

  Future<ThemeCubit> openCubit() async {
    final repo = _MockRepo();
    final store = _MockStore();
    when(() => store.read()).thenAnswer((_) async => null);
    when(() => store.write(any())).thenAnswer((_) async {});
    when(() => store.clear()).thenAnswer((_) async {});
    when(() => repo.load()).thenAnswer((_) async =>
        const ThemePreference(choice: ThemeChoice.light, open: true));
    when(() => repo.save(any(), idempotencyKey: any(named: 'idempotencyKey')))
        .thenAnswer((_) async =>
            const ThemePreference(choice: ThemeChoice.dark, open: true));
    final cubit = ThemeCubit(repository: repo, localStore: store);
    await cubit.load();
    return cubit;
  }

  testWidgets('the Appearance sheet offers all choices and applies Dark',
      (tester) async {
    final cubit = await openCubit();
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, state) => MaterialApp(
            theme: RvmTheme.light(),
            darkTheme: RvmTheme.dark(),
            themeMode: state.mode,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showAppearanceSheet(context),
                    child: const Text('Open appearance'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open appearance'));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(cubit.state.mode, ThemeMode.dark);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsNothing);
  });

  testWidgets('dark surfaces and small widths keep text legible',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: RvmTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(RvmSpacing.md),
              children: const [
                TeamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Today'),
                      SizedBox(height: RvmSpacing.sm),
                      Text('Punched in at 09:42'),
                      TextField(
                        decoration: InputDecoration(hintText: 'Add a remark'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor ?? RvmTheme.dark().scaffoldBackgroundColor,
        RvmPalette.dark.canvas);

    final context = tester.element(find.text('Today'));
    final palette = Theme.of(context).extension<RvmPalette>();
    expect(palette, RvmPalette.dark);
    expect(Theme.of(context).cardColor, RvmPalette.dark.card);
    expect(Theme.of(context).textTheme.bodyMedium?.color, RvmPalette.dark.ink);
    expect(tester.getSize(find.byType(TeamCard)).width, lessThanOrEqualTo(320));
  });
}

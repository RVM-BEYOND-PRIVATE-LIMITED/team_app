import 'package:core_network/core_network.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/theme/theme_cubit.dart';
import 'package:rvm_team_app/theme/theme_local_store.dart';
import 'package:rvm_team_app/theme/theme_preference.dart';
import 'package:rvm_team_app/theme/theme_preferences_repository.dart';

class MockThemePreferencesRepository extends Mock
    implements ThemePreferencesRepository {}

class MockThemeLocalStore extends Mock implements ThemeLocalStore {}

void main() {
  late MockThemePreferencesRepository repo;
  late MockThemeLocalStore store;

  setUpAll(() {
    registerFallbackValue(ThemeChoice.light);
    registerFallbackValue(
        const ThemePreference(choice: ThemeChoice.light, open: true));
  });

  setUp(() {
    repo = MockThemePreferencesRepository();
    store = MockThemeLocalStore();
    when(() => store.write(any())).thenAnswer((_) async {});
    when(() => store.clear()).thenAnswer((_) async {});
  });

  ThemeCubit build() =>
      ThemeCubit(repository: repo, localStore: store);

  test('closed switch forces Light and clears the kept choice', () async {
    when(() => store.read()).thenAnswer(
        (_) async => const ThemePreference(choice: ThemeChoice.dark, open: true));
    when(() => repo.load())
        .thenAnswer((_) async => const ThemePreference(
            choice: ThemeChoice.light, open: false));

    final cubit = build();
    await cubit.load();

    expect(cubit.state.open, isFalse);
    expect(cubit.state.mode, ThemeMode.light);
    expect(cubit.state.choice, ThemeChoice.light);
    verify(() => store.clear()).called(1);
  });

  test('a pilot Dark choice applies and is cached', () async {
    when(() => store.read()).thenAnswer((_) async => null);
    when(() => repo.load())
        .thenAnswer((_) async => const ThemePreference(
            choice: ThemeChoice.dark, open: true));

    final cubit = build();
    await cubit.load();

    expect(cubit.state.open, isTrue);
    expect(cubit.state.mode, ThemeMode.dark);
    expect(cubit.state.choice, ThemeChoice.dark);
    verify(() => store.write(
        const ThemePreference(choice: ThemeChoice.dark, open: true))).called(1);
  });

  test('select applies at once and saves with one key', () async {
    when(() => store.read()).thenAnswer((_) async => null);
    when(() => repo.load())
        .thenAnswer((_) async => const ThemePreference(
            choice: ThemeChoice.system, open: true));
    when(() => repo.save(any(), idempotencyKey: any(named: 'idempotencyKey')))
        .thenAnswer((_) async => const ThemePreference(
            choice: ThemeChoice.dark, open: true));

    final cubit = build();
    await cubit.load();
    await cubit.select(ThemeChoice.dark);

    expect(cubit.state.mode, ThemeMode.dark);
    expect(cubit.state.saving, isFalse);
    expect(cubit.state.pendingSave, isFalse);
    verify(() => repo.save(ThemeChoice.dark,
        idempotencyKey: any(named: 'idempotencyKey'))).called(1);
  });

  test('an offline save stays local and retries on resume', () async {
    when(() => store.read()).thenAnswer((_) async => null);
    when(() => repo.load())
        .thenAnswer((_) async => const ThemePreference(
            choice: ThemeChoice.light, open: true));
    when(() => repo.save(any(), idempotencyKey: any(named: 'idempotencyKey')))
        .thenThrow(const NoConnectionFailure());

    final cubit = build();
    await cubit.load();
    await cubit.select(ThemeChoice.dark);

    expect(cubit.state.mode, ThemeMode.dark);
    expect(cubit.state.pendingSave, isTrue);
    expect(cubit.state.saving, isFalse);

    when(() => repo.save(any(), idempotencyKey: any(named: 'idempotencyKey')))
        .thenAnswer((_) async => const ThemePreference(
            choice: ThemeChoice.dark, open: true));
    await cubit.resume();

    expect(cubit.state.pendingSave, isFalse);
    expect(cubit.state.mode, ThemeMode.dark);
  });

  test('sign-out returns the app to Light', () async {
    when(() => store.read()).thenAnswer((_) async => null);
    when(() => repo.load())
        .thenAnswer((_) async => const ThemePreference(
            choice: ThemeChoice.dark, open: true));

    final cubit = build();
    await cubit.load();
    await cubit.signOut();

    expect(cubit.state.mode, ThemeMode.light);
    expect(cubit.state.open, isFalse);
    verify(() => store.clear()).called(1);
  });
}

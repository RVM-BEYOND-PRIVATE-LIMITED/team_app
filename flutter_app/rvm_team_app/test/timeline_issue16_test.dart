import 'package:core_bloc/core_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/me/profile_screen.dart';
import 'package:rvm_team_app/injection.dart';

/// Regression tests for issues_image/issue16: the Timeline must show only the
/// important milestones, not every HR save ("Details updated" repeated for
/// every trivial update), and repeats of one line on one day collapse to one.
MyProfile _profileWithNoise() => MyProfile(
      employee: const MyProfileEmployee(
          id: '1', fullName: 'Test Faculty', noticePeriod: false),
      personal: const PersonalDetails(),
      timeline: [
        TimelineEvent(
            id: 't1', title: 'Details updated', at: DateTime(2026, 9, 28)),
        TimelineEvent(
            id: 't2', title: 'Details updated', at: DateTime(2026, 8, 26)),
        TimelineEvent(
            id: 't3', title: 'Details updated', at: DateTime(2026, 8, 26)),
        TimelineEvent(
            id: 't4', title: 'Branch changed', at: DateTime(2026, 8, 26)),
        TimelineEvent(
            id: 't5', title: 'Branch changed', at: DateTime(2026, 8, 26)),
        TimelineEvent(
            id: 't6',
            title: 'Reporting line changed',
            at: DateTime(2026, 8, 26)),
      ],
    );

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  testWidgets('timeline drops noise and dedupes repeats', (tester) async {
    getIt
      ..registerSingleton<LoadBloc<MyProfile>>(
          LoadBloc<MyProfile>(() async => _profileWithNoise()))
      ..registerSingleton<LoadBloc<PraisePage>>(LoadBloc<PraisePage>(
          () async => const PraisePage(praise: [], badges: [])));
    await tester
        .pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Trivial saves never reach the screen, however many the server sends.
    expect(find.text('Details updated'), findsNothing);
    // Important lines stay, once each per day.
    expect(find.text('Branch changed'), findsOneWidget);
    expect(find.text('Reporting line changed'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
  });
}

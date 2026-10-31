import 'package:core_bloc/core_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/me/profile_screen.dart';
import 'package:rvm_team_app/injection.dart';

MyProfile _profile() => const MyProfile(
      employee: MyProfileEmployee(
        id: '1',
        fullName: 'Test Faculty',
        noticePeriod: false,
      ),
      personal: PersonalDetails(),
      timeline: [],
    );

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  testWidgets('praise is drawn as a medal and opens its message',
      (tester) async {
    getIt
      ..registerSingleton<LoadBloc<MyProfile>>(
          LoadBloc<MyProfile>(() async => _profile()))
      ..registerSingleton<LoadBloc<PraisePage>>(LoadBloc<PraisePage>(
        () async => const PraisePage(
          badges: [
            PraiseBadge(id: 'mentor', label: 'Mentor', forGroup: 'people')
          ],
          praise: [
            WallPost(
              id: 'p1',
              kind: 'praise',
              mine: false,
              edited: false,
              hidden: false,
              deleted: false,
              badgeId: 'mentor',
              badgeLabel: 'Mentor',
              body: 'You always make time to help the team.',
              author: WallPerson(id: 'u2', fullName: 'Asha Rao'),
            ),
          ],
        ),
      ));

    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Praise received'), findsOneWidget);
    expect(find.text('Mentor'), findsOneWidget);
    expect(find.text('Asha Rao'), findsOneWidget);

    await tester.tap(find.text('Mentor'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Praise from Asha Rao'), findsOneWidget);
    expect(find.text('You always make time to help the team.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/wall/bloc/wall_bloc.dart';
import 'package:rvm_team_app/features/wall/wall_widgets.dart';

/// Backend `9310fb7` (contract 0.13.0) sends recent promotions and accepts a
/// `promotion` wish (migration 30). The card must offer Wish for a promotion
/// like it does for a birthday or anniversary.
class _MockEssRepository extends Mock implements EssRepository {}

const _promotion = CelebrationCard(
  employee: WallPerson(
      id: 'e2', fullName: 'Priya Sharma', employeeCode: 'RVM-021'),
  on: '2026-10-10',
);

const _celebrations = WallCelebrations(
  today: '2026-10-25',
  windowDays: 30,
  birthdays: [],
  anniversaries: [],
  newJoiners: [],
  promotions: [_promotion],
  hiddenCount: 0,
);

void main() {
  testWidgets('a promotion celebration offers Wish and sends occasion promotion',
      (tester) async {
    final repo = _MockEssRepository();
    when(() => repo.sendWish(
          employeeId: any(named: 'employeeId'),
          occasion: any(named: 'occasion'),
          body: any(named: 'body'),
        )).thenAnswer((_) async {});
    when(() => repo.wallCelebrations())
        .thenAnswer((_) async => _celebrations);
    final bloc = WallBloc(repo);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: BlocProvider<WallBloc>.value(
        value: bloc,
        child: const Scaffold(
          body: CelebrationsCard(celebrations: _celebrations),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Its own row: label, icon by kind, and a Wish action.
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.textContaining('Promotion'), findsOneWidget);
    expect(find.text('Wish'), findsOneWidget);

    await tester.tap(find.text('Wish'));
    await tester.pumpAndSettle();

    verify(() => repo.sendWish(
          employeeId: 'e2',
          occasion: 'promotion',
          body: any(named: 'body'),
        )).called(1);
  });

  test('the server kinds are parsed, including promotions', () {
    final celebrations = WallCelebrations.fromJson(const {
      'today': '2026-10-25',
      'window_days': 30,
      'birthdays': [],
      'anniversaries': [],
      'new_joiners': [],
      'promotions': [
        {
          'employee': {'id': 'e2', 'full_name': 'Priya Sharma'},
          'on': '2026-10-10',
          'wished_by_me': false,
          'wish_count': 2,
        }
      ],
      'birthdays_hidden': 0,
    });
    expect(celebrations.promotions, hasLength(1));
    expect(celebrations.promotions.single.employee.fullName, 'Priya Sharma');
    expect(celebrations.promotions.single.on, '2026-10-10');
    expect(celebrations.promotions.single.wishCount, 2);
    expect(celebrations.isEmpty, isFalse);
  });

  test('a timeline item carries its stable kind', () {
    final item = TimelineEvent.fromJson(const {
      'id': 't1',
      'kind': 'TRIVIAL_UPDATE',
      'title': 'Details updated',
      'at': '2026-10-15T05:00:00+00:00',
    });
    expect(item.kind, 'TRIVIAL_UPDATE');
  });
}

import 'package:core_bloc/core_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/domain/models.dart';
import 'package:rvm_team_app/features/work/my_batches_screen.dart';
import 'package:rvm_team_app/injection.dart';

/// Regression tests for issues_image/issue19: batch cards show the session
/// timing, and the status + search filters narrow the list.
List<TeamBatch> _batches() => const [
      TeamBatch(
        id: 'b1',
        name: 'ARTCAM_Morning',
        skillName: 'ARTCAM',
        facultyName: 'Mohit',
        students: 5,
        joinedCount: 5,
        status: 'Active',
        startTime: '10:00:00',
        endTime: '13:00:00',
        daysOfWeek: ['Monday', 'Wednesday', 'Friday'],
        schedule: '[1, 2, 3, 4, 5]',
        scheduleDays: [1, 2, 3, 4, 5],
        startDate: '2026-05-01',
        endDate: '2026-07-31',
      ),
      TeamBatch(
        id: 'b2',
        name: 'ARTCAM_Evening',
        skillName: 'ARTCAM',
        facultyName: 'Mohit',
        students: 3,
        joinedCount: 3,
        status: 'Completed',
        startTime: '18:00:00',
        endTime: '20:00:00',
        daysOfWeek: ['Tuesday', 'Thursday'],
      ),
    ];

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  testWidgets('timings show and filters narrow the list', (tester) async {
    getIt.registerSingleton<MyBatchesBloc>(
        LoadBloc<List<TeamBatch>>(() async => _batches()));
    await tester.pumpWidget(const MaterialApp(home: MyBatchesScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // design1 shell: header, subtitle, and no floating action button.
    expect(find.text('My batches'), findsOneWidget);
    expect(find.text('Instructor portal & schedules'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    // Card fields from the design: code, status badge, class roll, faculty.
    expect(find.textContaining('#BATCH-'), findsWidgets);
    expect(find.text('Class roll:'), findsOneWidget);
    expect(find.text('Faculty: Mohit'), findsWidgets);
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    // Timing, short days and dates render on the card.
    expect(find.textContaining('10:00 – 13:00'), findsOneWidget);
    expect(find.textContaining('Mon, Wed, Fri'), findsOneWidget);
    expect(find.text('ARTCAM_Morning'), findsOneWidget);
    expect(find.text('ARTCAM_Evening'), findsOneWidget);

    // Status filter: only completed batches remain.
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('ARTCAM_Morning'), findsNothing);
    expect(find.text('ARTCAM_Evening'), findsOneWidget);

    // Search narrows further; a miss shows the empty-filter note.
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'evening');
    await tester.pumpAndSettle();
    expect(find.text('ARTCAM_Morning'), findsNothing);
    expect(find.text('ARTCAM_Evening'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pumpAndSettle();
    expect(find.text('No batches match this filter.'), findsOneWidget);
  });
}

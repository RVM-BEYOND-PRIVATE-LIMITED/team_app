import 'package:core_bloc/core_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/work/bloc/absent_remark_bloc.dart';
import 'package:rvm_team_app/features/work/bloc/mark_attendance_bloc.dart';
import 'package:rvm_team_app/features/work/mark_attendance_screen.dart';
import 'package:rvm_team_app/injection.dart';

/// H1 (decision 8): class marking goes through the ESS, not the Scheduler.
class _MockEssRepository extends Mock implements EssRepository {}

const _date = '2026-10-26';

const _aarav = ClassRosterStudent(
  id: 's1',
  fullName: 'Aarav Sharma',
  admissionNumber: 'ADM-001',
  marked: 'present',
);

const _diya = ClassRosterStudent(
  id: 's2',
  fullName: 'Diya Patel',
  admissionNumber: 'ADM-002',
  marked: 'absent',
  absentReason: 'Fever, informed the office.',
);

ClassRoster _roster({bool canEdit = true}) => ClassRoster(
      batchId: 'b1',
      batchName: 'CAD Morning Batch',
      date: _date,
      alreadyMarked: !canEdit,
      canEdit: canEdit,
      students: const [_aarav, _diya],
    );

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  test('parses the ESS roster shape, including the lock', () {
    final roster = ClassRoster.fromJson(const {
      'batch': {'id': 'b1', 'name': 'CAD Morning Batch'},
      'date': _date,
      'already_marked': true,
      'can_edit': false,
      'students': [
        {
          'id': 's1',
          'full_name': 'Aarav Sharma',
          'admission_number': 'ADM-001',
          'marked': 'present',
          'absent_reason': null,
          'follow_up_comment': null,
        },
        {
          'id': 's2',
          'full_name': 'Diya Patel',
          'admission_number': 'ADM-002',
          'marked': 'absent',
          'absent_reason': 'Fever, informed the office.',
          'follow_up_comment': 'Call the parent.',
        }
      ],
    });
    expect(roster.batchName, 'CAD Morning Batch');
    expect(roster.alreadyMarked, isTrue);
    expect(roster.canEdit, isFalse);
    expect(roster.students, hasLength(2));
    expect(roster.students.first.isPresent, isTrue);
    expect(roster.students.last.isAbsent, isTrue);
    expect(roster.students.last.followUpComment, 'Call the parent.');
  });

  test('loads the ESS roster and maps the marks', () async {
    final repo = _MockEssRepository();
    when(() => repo.classRoster(
        batchId: any(named: 'batchId'),
        date: any(named: 'date'))).thenAnswer((_) async => _roster());
    final bloc =
        MarkAttendanceBloc(repo, batchId: 'b1', date: DateTime(2026, 10, 26));
    addTearDown(bloc.close);

    bloc.add(const MarkRosterRequested());
    final state =
        await bloc.stream.firstWhere((s) => s.status == LoadStatus.success);

    expect(state.students, hasLength(2));
    expect(state.present, {'s1': true, 's2': false});
    expect(state.canEdit, isTrue);
    verify(() => repo.classRoster(batchId: 'b1', date: _date)).called(1);
  });

  test('saves through the ESS and reads the server lock back', () async {
    final repo = _MockEssRepository();
    var reads = 0;
    when(() => repo.classRoster(
        batchId: any(named: 'batchId'),
        date: any(named: 'date'))).thenAnswer((_) async {
      reads += 1;
      return _roster(canEdit: reads == 1);
    });
    when(() => repo.saveClassAttendance(
          batchId: any(named: 'batchId'),
          date: any(named: 'date'),
          present: any(named: 'present'),
          absentReasons: any(named: 'absentReasons'),
          followUps: any(named: 'followUps'),
        )).thenAnswer((_) async {});
    final bloc =
        MarkAttendanceBloc(repo, batchId: 'b1', date: DateTime(2026, 10, 26));
    addTearDown(bloc.close);

    bloc.add(const MarkRosterRequested());
    await bloc.stream.firstWhere((s) => s.status == LoadStatus.success);

    bloc.add(const MarkSubmitted());
    final locked =
        await bloc.stream.firstWhere((s) => !s.canEdit && s.alreadyMarked);

    expect(locked.presentCount, 1);
    verify(() => repo.saveClassAttendance(
          batchId: 'b1',
          date: _date,
          present: {'s1': true, 's2': false},
          absentReasons: {
            's1': null,
            's2': 'Fever, informed the office.',
          },
          followUps: {'s1': null, 's2': null},
        )).called(1);
    verify(() => repo.classRoster(batchId: 'b1', date: _date)).called(2);
  });

  test('writes an absent reason through the ESS route', () async {
    final repo = _MockEssRepository();
    when(() => repo.updateClassRemark(
          batchId: any(named: 'batchId'),
          date: any(named: 'date'),
          studentId: any(named: 'studentId'),
          absentReason: any(named: 'absentReason'),
          followUpComment: any(named: 'followUpComment'),
        )).thenAnswer((_) async => const ClassRosterStudent(
          id: 's2',
          fullName: 'Diya Patel',
          marked: 'absent',
          absentReason: 'Fever, informed the office.',
        ));
    final bloc = AbsentRemarkBloc(repo);
    addTearDown(bloc.close);

    bloc.add(const AbsentRemarkSubmitted(
      batchId: 'b1',
      date: _date,
      studentId: 's2',
      reason: 'Fever, informed the office.',
      followUp: 'Call the parent.',
    ));
    final state =
        await bloc.stream.firstWhere((s) => s.status == WriteStatus.success);

    expect(state.forStudentId, 's2');
    verify(() => repo.updateClassRemark(
          batchId: 'b1',
          date: _date,
          studentId: 's2',
          absentReason: 'Fever, informed the office.',
          followUpComment: 'Call the parent.',
        )).called(1);
  });

  testWidgets('a marked day is locked but an absent reason stays editable',
      (tester) async {
    final repo = _MockEssRepository();
    when(() => repo.classRoster(
            batchId: any(named: 'batchId'), date: any(named: 'date')))
        .thenAnswer((_) async => _roster(canEdit: false));
    getIt.registerFactoryParam<MarkAttendanceBloc, String, DateTime>(
        (batchId, date) =>
            MarkAttendanceBloc(repo, batchId: batchId, date: date));

    await tester.pumpWidget(
        const MaterialApp(home: MarkAttendanceScreen(batchId: 'b1')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('The marks are locked'), findsOneWidget);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Diya Patel'), findsOneWidget);
    final saveFinder = find.ancestor(
      of: find.text('Save attendance'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    );
    expect(tester.widget<FilledButton>(saveFinder.first).onPressed, isNull);
    // Diya is marked absent, so her reason can still be filled.
    expect(find.byTooltip('Absent reason'), findsOneWidget);
  });
}

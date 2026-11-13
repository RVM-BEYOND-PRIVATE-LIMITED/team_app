import 'dart:async';

import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/inbox/faculty_attendance_inbox.dart';
import 'package:rvm_team_app/features/inbox/inbox_screen.dart';
import 'package:rvm_team_app/features/work/bloc/mark_attendance_bloc.dart';
import 'package:rvm_team_app/features/work/mark_attendance_screen.dart';
import 'package:rvm_team_app/injection.dart';
import 'package:rvm_team_app/router/app_router.dart';

/// Issue #57, the parts that need no backend change: the roster's fee-hold
/// flag in the model (item 2), refreshing the roster in place (item 4, first
/// half), and one tap from today's classes to marking that works as before
/// (item 11 as far as this change goes, and the marking half of check 9).
class _MockEssRepository extends Mock implements EssRepository {}

class _MockTeamAuthBloc extends Mock implements TeamAuthBloc {}

const _date = '2026-10-26';

const _one = ClassRosterStudent(
    id: 's1', fullName: 'Test Student One', admissionNumber: 'ADM-T01');
const _two = ClassRosterStudent(
    id: 's2', fullName: 'Test Student Two', admissionNumber: 'ADM-T02');
const _three = ClassRosterStudent(
    id: 's3', fullName: 'Test Student Three', admissionNumber: 'ADM-T03');

ClassRosterStudent _marked(ClassRosterStudent s, String mark) =>
    ClassRosterStudent(
      id: s.id,
      fullName: s.fullName,
      admissionNumber: s.admissionNumber,
      marked: mark,
    );

/// Nobody has saved the day: no marks, and a teaching role may edit it.
ClassRoster _unsaved(List<ClassRosterStudent> students) => ClassRoster(
      batchId: 'b1',
      batchName: 'Test_Morning_Batch',
      date: _date,
      alreadyMarked: false,
      canEdit: true,
      students: students,
    );

/// The day has rows. `can_edit` stays true only for an admin role.
ClassRoster _saved(List<ClassRosterStudent> students,
        {required bool canEdit}) =>
    ClassRoster(
      batchId: 'b1',
      batchName: 'Test_Morning_Batch',
      date: _date,
      alreadyMarked: true,
      canEdit: canEdit,
      students: students,
    );

/// Answers each roster read with the next reply (a roster, a [Failure] to
/// throw, or a [Completer] to wait on); the last reply repeats.
void _answerRoster(_MockEssRepository repo, List<Object> replies) {
  var calls = 0;
  when(() => repo.classRoster(
      batchId: any(named: 'batchId'),
      date: any(named: 'date'))).thenAnswer((_) async {
    final reply = replies[calls < replies.length ? calls : replies.length - 1];
    calls++;
    if (reply is Completer<ClassRoster>) return reply.future;
    if (reply is Failure) throw reply;
    return reply as ClassRoster;
  });
}

void _answerSave(_MockEssRepository repo, [Future<void> Function()? save]) {
  when(() => repo.saveClassAttendance(
        batchId: any(named: 'batchId'),
        date: any(named: 'date'),
        present: any(named: 'present'),
        absentReasons: any(named: 'absentReasons'),
        followUps: any(named: 'followUps'),
      )).thenAnswer((_) => save == null ? Future<void>.value() : save());
}

MarkAttendanceBloc _bloc(_MockEssRepository repo) {
  final bloc =
      MarkAttendanceBloc(repo, batchId: 'b1', date: DateTime(2026, 10, 26));
  addTearDown(bloc.close);
  return bloc;
}

Future<void> _loaded(MarkAttendanceBloc bloc) async {
  bloc.add(const MarkRosterRequested());
  await bloc.stream.firstWhere(
      (s) => s.status == LoadStatus.success || s.status == LoadStatus.empty);
}

Future<String?> _refresh(MarkAttendanceBloc bloc) {
  final done = Completer<String?>();
  bloc.add(MarkRosterRefreshed(done: done));
  return done.future;
}

void _registerMarkBloc(_MockEssRepository repo) {
  getIt.registerFactoryParam<MarkAttendanceBloc, String, DateTime>(
      (batchId, date) =>
          MarkAttendanceBloc(repo, batchId: batchId, date: date));
}

Future<void> _pumpMarkScreen(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
      home: MarkAttendanceScreen(
          batchId: 'b1', batchName: 'Test_Morning_Batch')));
  await tester.pumpAndSettle();
}

bool _ticked(WidgetTester tester, String name) => tester
    .widget<CheckboxListTile>(find.ancestor(
        of: find.text(name), matching: find.byType(CheckboxListTile)))
    .value!;

/// Drags the list down far enough for the RefreshIndicator to fire.
Future<void> _pullDown(WidgetTester tester, Finder from) async {
  await tester.fling(from, const Offset(0, 300), 1000);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// Sends a lifecycle change the way the engine does, on `flutter/lifecycle`;
/// the binding walks through every state in between.
Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {});
  await tester.pump();
}

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  group('item 2: the fee-hold flag on a roster student', () {
    test('today\'s roster reply has no fee_hold: every student reads false',
        () {
      // The exact keys classMarking.js studentView sends today.
      final roster = ClassRoster.fromJson(const {
        'batch': {'id': 'b1', 'name': 'Test_Morning_Batch'},
        'date': _date,
        'already_marked': false,
        'can_edit': true,
        'students': [
          {
            'id': 's1',
            'full_name': 'Test Student One',
            'admission_number': 'ADM-T01',
            'marked': null,
            'absent_reason': null,
            'follow_up_comment': null,
          },
          {
            'id': 's2',
            'full_name': 'Test Student Two',
            'admission_number': 'ADM-T02',
            'marked': 'absent',
            'absent_reason': 'Unwell, informed the office.',
            'follow_up_comment': null,
          },
        ],
      });

      expect(roster.students, hasLength(2));
      expect(roster.students.map((s) => s.feeHold), everyElement(isFalse));
      expect(roster.students.last.isAbsent, isTrue);
      expect(roster.students.last.absentReason, 'Unwell, informed the office.');
    });

    test('fee_hold true reads true; false, null or a non-boolean reads false',
        () {
      ClassRosterStudent parse(Object? value) =>
          ClassRosterStudent.fromJson({'id': 's1', 'fee_hold': value});

      expect(parse(true).feeHold, isTrue);
      expect(parse(false).feeHold, isFalse);
      expect(parse(null).feeHold, isFalse);
      expect(parse('true').feeHold, isFalse);
      expect(parse(1).feeHold, isFalse);
    });

    test('defaults to false and is part of equality', () {
      expect(_one.feeHold, isFalse);
      const held = ClassRosterStudent(
          id: 's1',
          fullName: 'Test Student One',
          admissionNumber: 'ADM-T01',
          feeHold: true);
      expect(held, isNot(equals(_one)));
      expect(
          ClassRosterStudent.fromJson(const {
            'id': 's1',
            'full_name': 'Test Student One',
            'admission_number': 'ADM-T01',
            'fee_hold': true,
          }),
          held);
    });
  });

  group('item 4: refreshing the roster in place', () {
    test('re-reads without the full-screen loader and keeps unsaved toggles',
        () async {
      final repo = _MockEssRepository();
      // s2 leaves the roster and s3 joins between the two reads.
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        _unsaved(const [_one, _three]),
      ]);
      final bloc = _bloc(repo);
      await _loaded(bloc);
      bloc.add(const MarkToggled('s1'));
      await bloc.stream.firstWhere((s) => s.present['s1'] == true);

      final seen = <MarkAttendanceState>[];
      final sub = bloc.stream.listen(seen.add);
      addTearDown(sub.cancel);
      expect(await _refresh(bloc), isNull);
      await Future<void>.delayed(Duration.zero);

      expect(seen, isNotEmpty);
      expect(seen.map((s) => s.status), isNot(contains(LoadStatus.loading)));
      expect(bloc.state.status, LoadStatus.success);
      expect(bloc.state.students.map((s) => s.id), ['s1', 's3']);
      // The toggle survives; the student who left is never sent on save.
      expect(bloc.state.present, {'s1': true, 's3': false});
      expect(bloc.state.canEdit, isTrue);
      verify(() => repo.classRoster(batchId: 'b1', date: _date)).called(2);
    });

    test('once the day is saved elsewhere, takes the server marks and lock',
        () async {
      final repo = _MockEssRepository();
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        _saved([_marked(_one, 'present'), _marked(_two, 'absent')],
            canEdit: false),
      ]);
      final bloc = _bloc(repo);
      await _loaded(bloc);
      bloc.add(const MarkToggled('s2'));
      await bloc.stream.firstWhere((s) => s.present['s2'] == true);

      expect(await _refresh(bloc), isNull);

      expect(bloc.state.present, {'s1': true, 's2': false});
      expect(bloc.state.alreadyMarked, isTrue);
      expect(bloc.state.canEdit, isFalse);
    });

    test('an admin correcting a saved day keeps the marks changed here',
        () async {
      final repo = _MockEssRepository();
      _answerRoster(repo, [
        _saved([_marked(_one, 'present'), _marked(_two, 'absent')],
            canEdit: true),
        // s1 was changed on the web meanwhile; s2 was not.
        _saved([_marked(_one, 'absent'), _marked(_two, 'absent')],
            canEdit: true),
      ]);
      final bloc = _bloc(repo);
      await _loaded(bloc);
      bloc.add(const MarkToggled('s2'));
      await bloc.stream.firstWhere((s) => s.present['s2'] == true);

      expect(await _refresh(bloc), isNull);

      expect(bloc.state.present, {'s1': false, 's2': true});
      expect(bloc.state.canEdit, isTrue);
    });

    test('is skipped while a save runs; the save reads the lock back',
        () async {
      final repo = _MockEssRepository();
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        _saved([_marked(_one, 'present'), _marked(_two, 'absent')],
            canEdit: false),
      ]);
      final saving = Completer<void>();
      _answerSave(repo, () => saving.future);
      final bloc = _bloc(repo);
      await _loaded(bloc);
      bloc.add(const MarkToggled('s1'));
      bloc.add(const MarkSubmitted());
      await bloc.stream
          .firstWhere((s) => s.writeStatus == WriteStatus.submitting);

      expect(await _refresh(bloc), isNull);
      verify(() => repo.classRoster(batchId: 'b1', date: _date)).called(1);

      saving.complete();
      final locked = await bloc.stream.firstWhere((s) => !s.canEdit);
      expect(locked.writeStatus, WriteStatus.success);
      verify(() => repo.classRoster(batchId: 'b1', date: _date)).called(1);
    });

    test('a slower reply never overwrites the lock a save read back', () async {
      final repo = _MockEssRepository();
      final slow = Completer<ClassRoster>();
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        slow,
        _saved([_marked(_one, 'present'), _marked(_two, 'absent')],
            canEdit: false),
      ]);
      _answerSave(repo);
      final bloc = _bloc(repo);
      await _loaded(bloc);
      bloc.add(const MarkToggled('s1'));
      await bloc.stream.firstWhere((s) => s.present['s1'] == true);

      final refreshed = _refresh(bloc);
      await Future<void>.delayed(Duration.zero);
      bloc.add(const MarkSubmitted());
      await bloc.stream.firstWhere((s) => !s.canEdit);

      // The refresh asked before the save; its reply is older than the lock.
      slow.complete(_unsaved(const [_one, _two]));
      expect(await refreshed, isNull);

      expect(bloc.state.canEdit, isFalse);
      expect(bloc.state.alreadyMarked, isTrue);
      expect(bloc.state.present, {'s1': true, 's2': false});
    });

    test('a toggle made while the read is on its way survives the reply',
        () async {
      final repo = _MockEssRepository();
      final slow = Completer<ClassRoster>();
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        slow
      ]);
      final bloc = _bloc(repo);
      await _loaded(bloc);

      final refreshed = _refresh(bloc);
      await Future<void>.delayed(Duration.zero);
      bloc.add(const MarkToggled('s2'));
      await bloc.stream.firstWhere((s) => s.present['s2'] == true);
      slow.complete(_unsaved(const [_one, _two]));

      expect(await refreshed, isNull);
      expect(bloc.state.present, {'s1': false, 's2': true});
    });

    test('a failed read keeps the roster and the marks and gives the reason',
        () async {
      final repo = _MockEssRepository();
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        const NoConnectionFailure(),
      ]);
      final bloc = _bloc(repo);
      await _loaded(bloc);
      bloc.add(const MarkToggled('s1'));
      await bloc.stream.firstWhere((s) => s.present['s1'] == true);

      expect(await _refresh(bloc), 'No internet connection');

      expect(bloc.state.status, LoadStatus.success);
      expect(bloc.state.students, const [_one, _two]);
      expect(bloc.state.present, {'s1': true, 's2': false});
      expect(bloc.state.error, isNull);
    });

    test('a pull during another read waits for it and gets its failure',
        () async {
      final repo = _MockEssRepository();
      final slow = Completer<ClassRoster>();
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        slow,
      ]);
      final bloc = _bloc(repo);
      await _loaded(bloc);

      // The silent read made on coming back to the app is on its way.
      bloc.add(const MarkRosterRefreshed());
      await Future<void>.delayed(Duration.zero);
      final pull = Completer<String?>();
      bloc.add(MarkRosterRefreshed(done: pull));
      await Future<void>.delayed(Duration.zero);

      // The pull's spinner stays up: no answer before the read's reply.
      expect(pull.isCompleted, isFalse);

      slow.completeError(const NoConnectionFailure());
      expect(await pull.future, 'No internet connection');
      // One read, shared: the pull did not start a second one.
      verify(() => repo.classRoster(batchId: 'b1', date: _date)).called(2);
      expect(bloc.state.students, const [_one, _two]);
    });

    test('does nothing while the first load is still running', () async {
      final repo = _MockEssRepository();
      final first = Completer<ClassRoster>();
      _answerRoster(repo, [first]);
      final bloc = _bloc(repo);
      bloc.add(const MarkRosterRequested());
      await bloc.stream.firstWhere((s) => s.status == LoadStatus.loading);

      expect(await _refresh(bloc), isNull);
      verify(() => repo.classRoster(batchId: 'b1', date: _date)).called(1);

      first.complete(_unsaved(const [_one]));
      await bloc.stream.firstWhere((s) => s.status == LoadStatus.success);
    });

    testWidgets('pulling the roster down re-reads it in place', (tester) async {
      final repo = _MockEssRepository();
      final second = Completer<ClassRoster>();
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        second
      ]);
      _registerMarkBloc(repo);
      await _pumpMarkScreen(tester);
      await tester.tap(find.text('Test Student One'));
      await tester.pump();
      expect(_ticked(tester, 'Test Student One'), isTrue);

      await _pullDown(tester, find.text('Test Student One'));

      // While the read runs: the list stays, with the pull spinner only.
      verify(() => repo.classRoster(batchId: 'b1', date: any(named: 'date')))
          .called(2);
      expect(find.text('Loading roster'), findsNothing);
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      expect(find.text('Test Student Two'), findsOneWidget);

      second.complete(_unsaved(const [_one, _two, _three]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Test Student Three'), findsOneWidget);
      expect(_ticked(tester, 'Test Student One'), isTrue);
      expect(find.text('1 of 3 present'), findsOneWidget);
    });

    testWidgets('a failed pull keeps the list and shows the real reason',
        (tester) async {
      final repo = _MockEssRepository();
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        const NoConnectionFailure(),
      ]);
      _registerMarkBloc(repo);
      await _pumpMarkScreen(tester);
      await tester.tap(find.text('Test Student One'));
      await tester.pump();

      await _pullDown(tester, find.text('Test Student One'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('No internet connection'), findsOneWidget);
      expect(find.text('Test Student Two'), findsOneWidget);
      expect(_ticked(tester, 'Test Student One'), isTrue);
    });

    testWidgets('an empty roster can be pulled down too', (tester) async {
      final repo = _MockEssRepository();
      _answerRoster(repo, [
        _unsaved(const []),
        _unsaved(const [_one]),
      ]);
      _registerMarkBloc(repo);
      await _pumpMarkScreen(tester);
      expect(
          find.text('No students are linked to this batch.'), findsOneWidget);

      await _pullDown(
          tester, find.text('No students are linked to this batch.'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Test Student One'), findsOneWidget);
      verify(() => repo.classRoster(batchId: 'b1', date: any(named: 'date')))
          .called(2);
    });

    testWidgets('coming back to the app re-reads the roster, keeping toggles',
        (tester) async {
      final repo = _MockEssRepository();
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        _unsaved(const [_one, _two, _three]),
      ]);
      _registerMarkBloc(repo);
      // The app is in the foreground when the screen opens.
      await _lifecycle(tester, AppLifecycleState.resumed);
      await _pumpMarkScreen(tester);
      await tester.tap(find.text('Test Student One'));
      await tester.pump();

      // Leaving the app reads nothing; coming back reads the roster once.
      await _lifecycle(tester, AppLifecycleState.paused);
      verify(() => repo.classRoster(batchId: 'b1', date: any(named: 'date')))
          .called(1);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      verify(() => repo.classRoster(batchId: 'b1', date: any(named: 'date')))
          .called(1);
      expect(find.text('Loading roster'), findsNothing);
      expect(find.text('Test Student Three'), findsOneWidget);
      expect(_ticked(tester, 'Test Student One'), isTrue);
    });

    testWidgets('a focus change while the app stays in view reads nothing',
        (tester) async {
      final repo = _MockEssRepository();
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        _unsaved(const [_one, _two, _three]),
      ]);
      _registerMarkBloc(repo);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await _pumpMarkScreen(tester);

      // The notification shade, a system dialog or split screen takes focus
      // and gives it back: the engine reports inactive, then resumed.
      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      verify(() => repo.classRoster(batchId: 'b1', date: any(named: 'date')))
          .called(1);
      expect(find.text('Test Student Three'), findsNothing);
    });
  });

  // What this group pins: the screen behind a teaching role's Attendance tab
  // (InboxScreen) lists today's classes, and one tap on a class opens the
  // app's own marking route, where marking works as before. What it does not
  // pin: where a sign-in lands. That is the Home tab (TeamShell starts on
  // index 0), whose "Today's classes" card links to My batches and lists no
  // classes, so the landing half of check 9 is still open on #57.
  group('item 11 and check 9 (marking half): today\'s classes to marking', () {
    const day = FacultyDay(
      date: _date,
      sessions: [
        FacultySession(
          id: 'b1',
          name: 'Test_Morning_Batch',
          startTime: '09:00',
          endTime: '11:00',
          locationName: 'Test Centre',
          covered: false,
          students: 2,
          marked: false,
        ),
      ],
      pendingRemarks: 0,
      sessionsToday: 1,
      markedToday: 0,
      todayPercentage: 0,
      monthExpected: 0,
      monthMarked: 0,
      monthPercentage: 0,
      activeStudents: 2,
      totalStudents: 2,
      sessionsWithoutAttendance: 1,
    );

    _MockTeamAuthBloc signedInAs(AppRole role) {
      final auth = _MockTeamAuthBloc();
      when(() => auth.state).thenReturn(TeamAuthState(
        status: TeamAuthStatus.authenticated,
        identity: StaffIdentity(userId: 'u1', role: role),
      ));
      when(() => auth.stream)
          .thenAnswer((_) => const Stream<TeamAuthState>.empty());
      return auth;
    }

    for (final role in const [AppRole.faculty, AppRole.hod]) {
      testWidgets(
          '${role.name}: the Attendance tab\'s screen lists today\'s classes',
          (tester) async {
        getIt.registerFactory<LoadBloc<FacultyDay>>(
            () => LoadBloc<FacultyDay>(() async => day));

        await tester.pumpWidget(MaterialApp(
          home: BlocProvider<TeamAuthBloc>.value(
            value: signedInAs(role),
            child: const InboxScreen(),
          ),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(FacultyAttendanceInbox), findsOneWidget);
        expect(find.text("Today's batches"), findsOneWidget);
        expect(find.text('Test Morning Batch'), findsOneWidget);
        expect(find.text('Mark'), findsOneWidget);
      });
    }

    testWidgets('one tap on a class opens marking, which works as before',
        (tester) async {
      final repo = _MockEssRepository();
      _answerRoster(repo, [
        _unsaved(const [_one, _two]),
        _saved([_marked(_one, 'present'), _marked(_two, 'absent')],
            canEdit: false),
      ]);
      _answerSave(repo);
      _registerMarkBloc(repo);
      getIt.registerFactory<LoadBloc<FacultyDay>>(
          () => LoadBloc<FacultyDay>(() async => day));
      final auth = signedInAs(AppRole.faculty);

      // The app's own marking route, behind today's classes.
      final app = createRouter(auth);
      addTearDown(app.dispose);
      final markRoute = app.configuration.routes
          .whereType<GoRoute>()
          .firstWhere((r) => r.path == '/work/batch/:id/mark');
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const InboxScreen()),
        markRoute,
      ]);
      addTearDown(router.dispose);

      await tester.pumpWidget(BlocProvider<TeamAuthBloc>.value(
        value: auth,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Morning Batch'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
          tester
              .widget<MarkAttendanceScreen>(find.byType(MarkAttendanceScreen))
              .batchId,
          'b1');
      expect(find.text('0 of 2 present'), findsOneWidget);

      await tester.tap(find.text('Test Student One'));
      await tester.pump();
      await tester.tap(find.text('Save attendance'));
      await tester.pumpAndSettle();

      verify(() => repo.saveClassAttendance(
            batchId: 'b1',
            date: any(named: 'date'),
            present: {'s1': true, 's2': false},
            absentReasons: {'s1': null, 's2': null},
            followUps: {'s1': null, 's2': null},
          )).called(1);
      expect(find.text('Attendance saved.'), findsOneWidget);
      expect(find.textContaining('The marks are locked'), findsOneWidget);
    });
  });
}

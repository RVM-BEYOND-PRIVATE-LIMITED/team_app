import 'dart:convert';
import 'dart:typed_data';

import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/data/datasources/my_attendance_remote_data_source.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/data/repositories/leave_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/requests/approvals_screen.dart';
import 'package:rvm_team_app/features/requests/approvals_summary.dart';
import 'package:rvm_team_app/features/requests/bloc/approvals_bloc.dart';
import 'package:rvm_team_app/features/requests/bloc/request_failure.dart';
import 'package:rvm_team_app/features/requests/bloc/requests_bloc.dart';
import 'package:rvm_team_app/features/requests/raise_request_sheet.dart';
import 'package:rvm_team_app/features/requests/requests_screen.dart';
import 'package:rvm_team_app/injection.dart';
import 'package:rvm_team_app/push/push_service.dart';

import 'fixtures/scheduler_leave_fixtures.dart';

/// team_app #43 (leave on the Scheduler leave API, the Nov 2026 policy) and
/// #45 (leave pushes open the right screen; a real Approvals count). Every
/// Scheduler reply here is a real one from KP's feat/leave-policy branch.
class _MockEssRepository extends Mock implements EssRepository {}

class _MockLeaveRepository extends Mock implements LeaveRepository {}

class _MockCapabilitiesBloc extends Mock implements LoadBloc<EssCapabilities> {}

/// Answers each request with a canned status + JSON, and records it.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Object body;
  RequestOptions? captured;
  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    captured = options;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

(MyAttendanceRemoteDataSource, _Adapter) _remote(int status, Object body) {
  final adapter = _Adapter(status, body);
  final dio = Dio(BaseOptions(baseUrl: 'https://scheduler.test/api'))
    ..httpClientAdapter = adapter;
  return (MyAttendanceRemoteDataSource(dio), adapter);
}

const _caps = EssCapabilities(
  tabs: ['home', 'inbox', 'wall', 'team', 'me'],
  sectionTime: true,
  sectionHelpdesk: true,
  sectionDocuments: true,
  sectionProfile: true,
  sectionWork: false,
  hasReports: false,
  directReports: 0,
  approvalsOwnReports: false,
  approvalsAnyRequest: false,
  approvalRequestTypes: [],
  hrScope: [],
  wallPost: true,
  wallAnnounce: false,
  wallModerate: false,
  pushEnabled: true,
  integrityRequired: false,
);

EssRequest _essRequest(String id, String family, String type,
        {DateTime? createdAt}) =>
    EssRequest.fromJson({
      'id': id,
      'family': family,
      'type': type,
      'status': 'pending',
      'day': '2026-11-20',
      'reason': 'Reason here',
      'created_at': (createdAt ?? DateTime(2026, 11, 10)).toIso8601String(),
    });

void main() {
  setUpAll(() => registerFallbackValue(const LoadRequested()));
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  group('models from the real Scheduler replies', () {
    test('a Scheduler row is leave, from the Scheduler, with its approvers', () {
      final overview = LeaveOverview.fromJson(overviewShallu);
      final r = overview.approvals.single;
      expect(r.family, 'leave');
      expect(r.isLeave, isTrue);
      expect(r.isSchedulerLeave, isTrue);
      expect(r.secondApprovalNeeded, isTrue);
      expect(r.stage, 'manager');
      expect(r.approvalSendsOn, isTrue);
      expect(r.waitingSummary, 'Waiting on Shallu Chandra · since today');
      expect(overview.approvalsCount, 1);
      expect(overview.canApprove, isTrue);
      expect(overview.earliestSelfDay, isNotNull);
      expect(overview.shortNoticeMessage,
          'Leave in the next 3 days cannot be applied for here. Contact HR, who will enter it, and tell your approver. Leave can be applied for from the 4th day.');
    });

    test('an approved leave says what it was written as', () {
      final overview = LeaveOverview.fromJson(overviewFacultyAfter);
      final approved =
          overview.requests.firstWhere((r) => r.status == 'approved');
      expect(approved.writtenAsLabel, 'Written as 1 CL + 1 LWP');
      expect(approved.stageLabel, isNull);
      // The Scheduler sends no `offered`; every leave balance is shown.
      expect(overview.balances.every((b) => b.offered), isTrue);
    });

    test('the HR pool sees a leave waiting on "HR"', () {
      final overview = LeaveOverview.fromJson(overviewHarshitaHrpool);
      expect(overview.inHrPool, isTrue);
      expect(overview.approvals.single.waitingOn, 'HR');
      expect(overview.approvals.single.finalApproverIsHrPool, isTrue);
    });

    test('work-from-home rows of the shared table are left to the ESS', () {
      final withWfh = Map<String, dynamic>.from(overviewShallu)
        ..['approvals'] = [
          ...(overviewShallu['approvals'] as List),
          {...(overviewShallu['approvals'] as List).first as Map, 'id': 'w1', 'type': 'wfh'},
        ];
      final overview = LeaveOverview.fromJson(withWfh);
      expect(overview.approvals.map((r) => r.type), ['cl']);
    });

    test('the route reads "Goes to X, then Y", or one approver', () {
      expect(LeaveRoutePreview.fromJson(routeFaculty2d).route.summary,
          'Goes to Shallu Chandra, then Bhupender Singh');
      expect(LeaveRoutePreview.fromJson(routeEditor3d).route.summary,
          'Goes to Nisha Verma');
      expect(LeaveRoutePreview.fromJson(routeEditor4d).route.summary,
          'Goes to Nisha Verma, then HR');
    });

    test('a faculty leave 3 days ahead is flagged late notice', () {
      final r = EssRequest.fromSchedulerLeave(
          (case4Faculty3days['request'] as Map).cast<String, dynamic>());
      expect(r.lateNotice, isTrue);
    });

    test('a decision says whether it was sent on', () {
      expect(LeaveDecision.fromJson(case2ShalluApprove).advanced, isTrue);
      expect(LeaveDecision.fromJson(case2BhupenderApprove).outcome, 'approved');
    });

    test('a recorded-by-HR leave is marked as such', () {
      final r = EssRequest.fromSchedulerLeave({
        ...(case2FacultyFile['request'] as Map).cast<String, dynamic>(),
        'filed_via': 'hr_entry',
        'status': 'approved',
      });
      expect(r.isRecordedByHr, isTrue);
    });
  });

  group('data source (Scheduler /hr/my-attendance/leave)', () {
    test('files with spoke_to_approver as the JSON boolean true', () async {
      final (remote, adapter) = _remote(201, case2FacultyFile);
      final r = await remote.createLeave(
          type: 'cl',
          day: '2026-11-18',
          endDay: '2026-11-19',
          reason: 'Family function',
          spokeToApprover: true);
      expect(adapter.captured!.path, '/hr/my-attendance/leave');
      expect(adapter.captured!.method, 'POST');
      expect(adapter.captured!.data, {
        'type': 'cl',
        'day': '2026-11-18',
        'end_day': '2026-11-19',
        'portion': 'full',
        'reason': 'Family function',
        'spoke_to_approver': true,
      });
      expect(r.isSchedulerLeave, isTrue);
    });

    test('a short-notice refusal keeps the backend code and message', () async {
      final (remote, _) = _remote(409, case1TomorrowBlocked);
      await expectLater(
        remote.createLeave(
            type: 'cl', day: '2026-11-13', reason: 'Fever', spokeToApprover: true),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', 'LEAVE_SHORT_NOTICE')
            .having((f) => f.message, 'message', contains('Contact HR'))),
      );
    });

    test('decide sends the cover and reads the outcome', () async {
      final (remote, adapter) = _remote(200, case2ShalluApprove);
      final d = await remote.decideLeave('id-1',
          decision: 'approve', substituteFacultyId: 'f1', classTiming: '10-12');
      expect(adapter.captured!.path, '/hr/my-attendance/leave/id-1/decide');
      expect(adapter.captured!.data,
          {'decision': 'approve', 'substitute_faculty_id': 'f1', 'class_timing': '10-12'});
      expect(d.outcome, 'advanced');
    });

    test('self-approval reads as the fixed line', () async {
      final (remote, _) = _remote(403, case6SelfApproval);
      try {
        await remote.decideLeave('id-1', decision: 'approve');
        fail('expected a refusal');
      } on Failure catch (f) {
        expect(f.code, 'SELF_APPROVAL');
        expect(requestFailure(f).message, 'Nobody approves their own leave.');
      }
    });

    test('route, who is off and substitute faculty parse', () async {
      final (r1, a1) = _remote(200, routeFaculty2d);
      final route = await r1.leaveRoute(day: '2026-11-18', endDay: '2026-11-19');
      expect(a1.captured!.queryParameters,
          {'day': '2026-11-18', 'end_day': '2026-11-19', 'portion': 'full'});
      expect(route.route.secondNeeded, isTrue);
      final (r2, _) = _remote(200, whosOff);
      expect((await r2.leaveWhosOff('id-1')).off, isEmpty);
      final (r3, _) = _remote(200, facultyChoices);
      expect((await r3.leaveFaculty(requestId: 'id-1')).single.name, 'Anita Gupta');
    });
  });

  group('requests bloc', () {
    late _MockEssRepository ess;
    late _MockLeaveRepository leave;
    setUp(() {
      ess = _MockEssRepository();
      leave = _MockLeaveRepository();
      when(() => ess.leaveBalances(month: any(named: 'month'))).thenAnswer(
          (_) async => LeaveBalances.fromJson({
                'month': '2026-11',
                'types': [
                  {'type': 'fix_a_day', 'offered': true, 'allowed': 3, 'used': 0, 'pending': 0},
                  {'type': 'leave_cl', 'offered': true, 'allowed': 1, 'used': 0, 'pending': 0},
                ],
              }));
      when(() => ess.myAttendanceRequests())
          .thenAnswer((_) async => [_essRequest('a1', 'attendance', 'on_duty')]);
      // The ESS still lists CL from the shared table; only its WFH is kept.
      when(() => ess.myLeaveRequests()).thenAnswer((_) async => [
            _essRequest('w1', 'leave', 'wfh'),
            _essRequest('old-cl', 'leave', 'cl'),
          ]);
      when(() => leave.overviewSafe(month: any(named: 'month'))).thenAnswer(
          (_) async => (data: LeaveOverview.fromJson(overviewFacultyAfter), failure: null));
    });

    test('merges ESS attendance + WFH with Scheduler leave; balances from both',
        () async {
      final bloc = RequestsBloc(ess, leave)..add(const RequestsLoadRequested());
      await expectLater(bloc.stream,
          emitsThrough(isA<RequestsState>().having((s) => s.status, 'status', LoadStatus.success)));
      final s = bloc.state;
      expect(s.requests.map((r) => r.id), isNot(contains('old-cl')));
      expect(s.requests.any((r) => r.id == 'w1'), isTrue);
      expect(s.requests.any((r) => r.isSchedulerLeave), isTrue);
      final types = s.balances!.types.map((t) => t.type).toList();
      expect(types, contains('fix_a_day'));
      // The ESS leave_cl row is replaced by the Scheduler's.
      expect(types.where((t) => t == 'leave_cl').length, 1);
      expect(s.leave, isNotNull);
      await bloc.close();
    });

    test('one host down still shows the other, with the reason', () async {
      when(() => leave.overviewSafe(month: any(named: 'month'))).thenAnswer((_) async =>
          (data: null, failure: const ServerFailure('Leave policy not switched on')));
      final bloc = RequestsBloc(ess, leave)..add(const RequestsLoadRequested());
      await expectLater(bloc.stream,
          emitsThrough(isA<RequestsState>().having((s) => s.status, 'status', LoadStatus.success)));
      expect(bloc.state.leaveFailure, isNotNull);
      expect(bloc.state.requests, isNotEmpty);
      await bloc.close();
    });

    test('leave is filed on the Scheduler with the approver box', () async {
      when(() => leave.create(
              type: any(named: 'type'),
              day: any(named: 'day'),
              endDay: any(named: 'endDay'),
              portion: any(named: 'portion'),
              reason: any(named: 'reason'),
              spokeToApprover: any(named: 'spokeToApprover')))
          .thenAnswer((_) async => EssRequest.fromSchedulerLeave(
              (case2FacultyFile['request'] as Map).cast<String, dynamic>()));
      final bloc = RequestsBloc(ess, leave)
        ..add(const RequestCreateRequested(
            family: 'leave',
            type: 'cl',
            day: '2026-11-18',
            endDay: '2026-11-19',
            reason: 'Family function',
            spokeToApprover: true));
      await expectLater(bloc.stream,
          emitsThrough(isA<RequestsState>().having((s) => s.createdNonce, 'created', 1)));
      verify(() => leave.create(
          type: 'cl',
          day: '2026-11-18',
          endDay: '2026-11-19',
          portion: 'full',
          reason: 'Family function',
          spokeToApprover: true)).called(1);
      verifyNever(() => ess.createLeaveRequestSafe(
          type: any(named: 'type'),
          day: any(named: 'day'),
          endDay: any(named: 'endDay'),
          portion: any(named: 'portion'),
          reason: any(named: 'reason')));
      await bloc.close();
    });
  });

  group('approvals bloc', () {
    late _MockEssRepository ess;
    late _MockLeaveRepository leave;
    setUp(() {
      ess = _MockEssRepository();
      leave = _MockLeaveRepository();
      when(() => ess.approvals(status: any(named: 'status'))).thenAnswer((_) async =>
          ApprovalInbox(truncated: false, requests: [
            _essRequest('att-new', 'attendance', 'fix_a_day', createdAt: DateTime(2026, 11, 12)),
            _essRequest('ess-cl', 'leave', 'cl', createdAt: DateTime(2026, 11, 1)),
          ]));
      when(() => leave.overviewSafe(month: any(named: 'month'))).thenAnswer(
          (_) async => (data: LeaveOverview.fromJson(overviewShallu), failure: null));
    });

    test('merges both queues, drops ESS CL, oldest first', () async {
      final bloc = ApprovalsBloc(ess, leave)..add(const ApprovalsLoadRequested());
      await expectLater(bloc.stream,
          emitsThrough(isA<ApprovalsState>().having((s) => s.status, 'status', LoadStatus.success)));
      final rows = bloc.state.inbox!.requests;
      expect(rows.map((r) => r.id), isNot(contains('ess-cl')));
      expect(rows.length, 2);
      expect(rows.first.createdAt!.isBefore(rows.last.createdAt!), isTrue);
      expect(bloc.state.inbox!.leave, 1);
      expect(bloc.state.inbox!.attendance, 1);
      await bloc.close();
    });

    test('a leave decision goes to the Scheduler and reports "advanced"', () async {
      when(() => leave.decide(any(),
              decision: any(named: 'decision'),
              note: any(named: 'note'),
              substituteFacultyId: any(named: 'substituteFacultyId'),
              classTiming: any(named: 'classTiming')))
          .thenAnswer((_) async => LeaveDecision.fromJson(case2ShalluApprove));
      final bloc = ApprovalsBloc(ess, leave)..add(const ApprovalsLoadRequested());
      await expectLater(bloc.stream,
          emitsThrough(isA<ApprovalsState>().having((s) => s.status, 'status', LoadStatus.success)));
      final leaveRow = bloc.state.inbox!.requests.firstWhere((r) => r.isSchedulerLeave);
      bloc.add(ApprovalDecided(
          family: 'leave', id: leaveRow.id, decision: 'approve',
          substituteFacultyId: 'f1', classTiming: '10-12'));
      await expectLater(bloc.stream,
          emitsThrough(isA<ApprovalsState>().having((s) => s.decidedNonce, 'nonce', 1)));
      expect(bloc.state.lastOutcome, 'advanced');
      verifyNever(() => ess.decideRequest(
          family: any(named: 'family'),
          id: any(named: 'id'),
          decision: any(named: 'decision'),
          note: any(named: 'note'),
          substituteFacultyId: any(named: 'substituteFacultyId'),
          classTiming: any(named: 'classTiming')));
      await bloc.close();
    });
  });

  group('screens', () {
    testWidgets('apply sheet: new names, short-notice text, route, required box',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final leave = _MockLeaveRepository();
      when(() => leave.route(
              day: any(named: 'day'),
              endDay: any(named: 'endDay'),
              portion: any(named: 'portion')))
          .thenAnswer((_) async => LeaveRoutePreview.fromJson(routeFaculty2d));
      getIt.registerSingleton<LeaveRepository>(leave);
      final bloc = _FakeRequestsBloc(RequestsState(
          status: LoadStatus.success,
          leave: LeaveOverview.fromJson(overviewFacultyAfter)));
      await tester.pumpWidget(MaterialApp(
        home: BlocProvider<RequestsBloc>.value(
          value: bloc,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => showRaiseRequestSheet(context),
                  child: const Text('open')),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.tap(find.text('Leave'));
      await _settle(tester);

      expect(find.text('Leave (CL if available, else LWP)'), findsOneWidget);
      expect(
          find.text('Leave in the next 3 days cannot be applied for here. Contact HR, who will enter it, and tell your approver. Leave can be applied for from the 4th day.'),
          findsOneWidget);
      expect(find.text('Goes to Shallu Chandra, then Bhupender Singh'), findsOneWidget);
      expect(find.text('I have spoken to my approver about this leave.'), findsOneWidget);

      // Set the reason without focusing the field (no blinking cursor).
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Reason'))
          .controller!
          .text = 'Family function';
      await tester.tap(find.text('Send to approver'));
      await _settle(tester);
      expect(find.textContaining('I have spoken to my approver about this leave" first'),
          findsOneWidget);
      expect(bloc.added, isEmpty);

      await tester.tap(find.text('I have spoken to my approver about this leave.'));
      await tester.tap(find.text('Send to approver'));
      await _settle(tester);
      final sent = bloc.added.whereType<RequestCreateRequested>().single;
      expect(sent.family, 'leave');
      expect(sent.spokeToApprover, isTrue);
      // The day picker starts at earliest_self_day (today + 4), never sooner.
      expect(sent.day.compareTo(LeaveOverview.fromJson(overviewFacultyAfter).earliestSelfDay!),
          greaterThanOrEqualTo(0));
    });

    testWidgets('approvals: waiting and late-notice badges, own leave not approvable',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final overview = LeaveOverview.fromJson(overviewShallu);
      final mine = EssRequest.fromSchedulerLeave({
        ...(case4Faculty3days['request'] as Map).cast<String, dynamic>(),
        'id': 'own-1',
        'employee': {'id': overview.employeeId, 'full_name': 'Shallu Chandra'},
        'waiting_days': 3,
      });
      final ess = _MockEssRepository();
      final leave = _MockLeaveRepository();
      when(() => ess.approvals(status: any(named: 'status'))).thenAnswer(
          (_) async => const ApprovalInbox(requests: [], truncated: false));
      final withMine = LeaveOverview(
        month: overview.month,
        employeeId: overview.employeeId,
        approvals: [...overview.approvals, mine],
        approvalsCount: 2,
        canApprove: true,
      );
      when(() => leave.overviewSafe(month: any(named: 'month')))
          .thenAnswer((_) async => (data: withMine, failure: null));
      getIt.registerFactory<ApprovalsBloc>(() => ApprovalsBloc(ess, leave));
      await tester.pumpWidget(const MaterialApp(home: ApprovalsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Waiting since today'), findsOneWidget);
      expect(find.text('Waiting 3 days'), findsOneWidget);
      expect(find.text('Late notice'), findsOneWidget);
      expect(find.text('1st of 2 approvals · then Bhupender Singh'), findsOneWidget);
      expect(find.text('Who else is off'), findsNWidgets(2));
      expect(find.textContaining('This is your own leave.'), findsOneWidget);
      // Only the other person's leave can be approved.
      expect(find.text('Approve & send on'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
    });

    testWidgets('my requests: waiting on, written as, recorded by HR', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final overview = LeaveOverview.fromJson(overviewFacultyAfter);
      final pending = EssRequest.fromSchedulerLeave({
        ...(case2FacultyFile['request'] as Map).cast<String, dynamic>(),
        'waiting_days': 2,
      });
      final byHr = EssRequest.fromSchedulerLeave({
        ...(case4Faculty3days['request'] as Map).cast<String, dynamic>(),
        'id': 'hr-1',
        'status': 'approved',
        'filed_via': 'hr_entry',
        'lwp_units': 1,
      });
      final ess = _MockEssRepository();
      final leave = _MockLeaveRepository();
      when(() => ess.leaveBalances(month: any(named: 'month'))).thenAnswer(
          (_) async => const LeaveBalances(month: '2026-11', types: []));
      when(() => ess.myAttendanceRequests()).thenAnswer((_) async => const []);
      when(() => ess.myLeaveRequests()).thenAnswer((_) async => const []);
      when(() => leave.overviewSafe(month: any(named: 'month'))).thenAnswer((_) async => (
            data: LeaveOverview(
                month: overview.month,
                balances: overview.balances,
                requests: [...overview.requests, pending, byHr]),
            failure: null
          ));
      final caps = _MockCapabilitiesBloc();
      when(() => caps.state).thenReturn(
          const LoadState<EssCapabilities>(status: LoadStatus.success, data: _caps));
      when(() => caps.stream).thenAnswer((_) => const Stream.empty());
      when(() => caps.close()).thenAnswer((_) async {});
      getIt
        ..registerFactory<RequestsBloc>(() => RequestsBloc(ess, leave))
        ..registerFactory<CapabilitiesBloc>(() => caps);
      await tester.pumpWidget(const MaterialApp(home: RequestsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Waiting on Shallu Chandra · 2 days'), findsOneWidget);
      expect(find.text('Written as 1 CL + 1 LWP'), findsOneWidget);
      expect(find.text('Recorded by HR'), findsOneWidget);
      expect(find.textContaining('HOO'), findsNothing);
      expect(find.textContaining('Super Admin'), findsNothing);
    });
  });

  group('#45', () {
    test('a leave push opens Approvals for the approver, My requests for the employee',
        () {
      expect(requestRouteFor({'category': 'approvals', 'request_family': 'leave', 'request_id': 'r1'}),
          '/approvals');
      expect(requestRouteFor({'category': 'decisions', 'request_family': 'leave', 'request_id': 'r1'}),
          '/requests');
      expect(requestRouteFor({'category': 'praise'}), isNull);
      expect(requestRouteFor({'category': 'approvals'}), isNull);
    });

    test('the Approvals count is the leave approvals_count + ESS attendance', () async {
      final ess = _MockEssRepository();
      final leave = _MockLeaveRepository();
      when(() => ess.approvals(status: any(named: 'status'))).thenAnswer((_) async =>
          ApprovalInbox(truncated: false, requests: [
            _essRequest('att', 'attendance', 'on_duty'),
            _essRequest('ess-cl', 'leave', 'cl'),
          ]));
      when(() => leave.overviewSafe(month: any(named: 'month'))).thenAnswer(
          (_) async => (data: LeaveOverview.fromJson(overviewShallu), failure: null));
      final summary = await loadApprovalsSummary(ess, leave);
      expect(summary.pending, 2); // 1 attendance + approvals_count 1
      expect(summary.canApproveLeave, isTrue);
    });

    test('a mapping approver with no reports still gets the count', () async {
      final ess = _MockEssRepository();
      final leave = _MockLeaveRepository();
      when(() => ess.approvals(status: any(named: 'status')))
          .thenThrow(const ForbiddenFailure('Not an approver'));
      when(() => leave.overviewSafe(month: any(named: 'month'))).thenAnswer(
          (_) async => (data: LeaveOverview.fromJson(overviewShallu), failure: null));
      final summary = await loadApprovalsSummary(ess, leave);
      expect(summary.pending, 1);
      expect(summary.canApproveLeave, isTrue);
    });
  });
}

/// A RequestsBloc whose state is fixed and whose events are recorded.
class _FakeRequestsBloc extends Bloc<RequestsEvent, RequestsState>
    implements RequestsBloc {
  _FakeRequestsBloc(super.initial) {
    on<RequestsEvent>((e, _) => added.add(e));
  }
  final added = <RequestsEvent>[];
}

/// Fixed pumps: lets the sheet animate and the mocked route reply land
/// without waiting on every frame source to go idle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

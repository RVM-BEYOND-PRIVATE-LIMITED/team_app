import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/data/repositories/leave_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/requests/approvals_screen.dart';
import 'package:rvm_team_app/features/requests/bloc/approvals_bloc.dart';
import 'package:rvm_team_app/injection.dart';

import 'fixtures/scheduler_leave_fixtures.dart';

/// Issue #33 (teaching-leave cover), on the Scheduler leave API since #43:
/// the approver of a teaching leave still chooses the substitute and the class
/// timing before approving, and the decision goes to the Scheduler.
class _MockEssRepository extends Mock implements EssRepository {}

class _MockLeaveRepository extends Mock implements LeaveRepository {}

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  testWidgets(
      'a teaching leave asks its 1st approver for cover, then decides on the Scheduler',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final ess = _MockEssRepository();
    final leave = _MockLeaveRepository();
    final overview = LeaveOverview.fromJson(overviewShallu);
    final request = overview.approvals.single;
    when(() => ess.approvals(status: any(named: 'status'))).thenAnswer(
        (_) async => const ApprovalInbox(requests: [], truncated: false));
    when(() => leave.overviewSafe(month: any(named: 'month')))
        .thenAnswer((_) async => (data: overview, failure: null));
    when(() => leave.faculty(requestId: any(named: 'requestId'))).thenAnswer(
        (_) async => const [LeaveFacultyOption(id: 'f1', name: 'Anita Gupta')]);
    when(() => leave.decide(any(),
            decision: any(named: 'decision'),
            note: any(named: 'note'),
            substituteFacultyId: any(named: 'substituteFacultyId'),
            classTiming: any(named: 'classTiming')))
        .thenAnswer((_) async => LeaveDecision.fromJson(case2ShalluApprove));

    getIt
      ..registerSingleton<EssRepository>(ess)
      ..registerSingleton<LeaveRepository>(leave)
      ..registerFactory<ApprovalsBloc>(() => ApprovalsBloc(ess, leave));

    await tester.pumpWidget(const MaterialApp(home: ApprovalsScreen()));
    await tester.pumpAndSettle();

    // Two approvals (Shallu, then Bhupender): the 1st sends it on.
    expect(request.isTeaching, isTrue);
    expect(find.text('Approve & send on'), findsOneWidget);
    expect(find.textContaining('Super Admin'), findsNothing);
    await tester.tap(find.text('Approve & send on'));
    await tester.pumpAndSettle();

    expect(find.text('Coverage for teaching leave'), findsOneWidget);
    final dialogButton = find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Approve & send on'));
    await tester.tap(dialogButton);
    await tester.pumpAndSettle();
    expect(find.text('Give the class timing.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '10:00–11:30');
    await tester.tap(dialogButton);
    await tester.pumpAndSettle();

    verify(() => leave.decide(request.id,
        decision: 'approve',
        note: null,
        substituteFacultyId: 'f1',
        classTiming: '10:00–11:30')).called(1);
    verifyNever(() => ess.decideRequest(
        family: any(named: 'family'),
        id: any(named: 'id'),
        decision: any(named: 'decision'),
        note: any(named: 'note'),
        substituteFacultyId: any(named: 'substituteFacultyId'),
        classTiming: any(named: 'classTiming')));
    expect(find.text('Approved and sent on to the 2nd approver.'), findsOneWidget);
  });
}


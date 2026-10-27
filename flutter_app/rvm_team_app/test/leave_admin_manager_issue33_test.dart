import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/hr/leave_approvers_screen.dart';
import 'package:rvm_team_app/features/requests/approvals_screen.dart';
import 'package:rvm_team_app/features/requests/bloc/approvals_bloc.dart';
import 'package:rvm_team_app/injection.dart';

class _MockEssRepository extends Mock implements EssRepository {}

const _teachingLeave = EssRequest(
  id: 'r1',
  family: 'leave',
  type: 'cl',
  status: 'pending',
  day: '2026-11-12',
  endDay: '2026-11-13',
  dayCount: 2,
  requiresFinalApproval: true,
  stage: 'manager',
  adminManagerName: 'Asha Admin',
  isTeaching: true,
  managerApprovedByName: null,
  managerRemark: null,
  reason: 'Family function at home',
  employee: RequestEmployee(
      id: 'e1', fullName: 'Ravi Faculty', employeeCode: 'RVM/F/48'),
);

const _approvers = LeaveApproverList(branches: [
  LeaveApproverBranch(
    id: 'b1',
    name: 'Faridabad',
    selectedEmployeeId: 'm1',
    selectedName: 'Asha Admin',
    adminManagers: [
      LeaveApproverChoice(
          id: 'm1', fullName: 'Asha Admin', employeeCode: 'RVM-1'),
    ],
  ),
  LeaveApproverBranch(
    id: 'b2',
    name: 'Delhi',
    adminManagers: [
      LeaveApproverChoice(id: 'm2', fullName: 'Vikram Admin'),
      LeaveApproverChoice(id: 'm3', fullName: 'Neha Admin'),
    ],
  ),
  LeaveApproverBranch(id: 'b3', name: 'Mumbai', adminManagers: []),
]);

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  test('a leave row parses the Admin Manager round and coverage', () {
    final request = EssRequest.fromJson({
      'id': 'r1',
      'family': 'leave',
      'type': 'cl',
      'status': 'pending',
      'day': '2026-11-12',
      'end_day': '2026-11-13',
      'day_count': 2,
      'requires_final_approval': true,
      'stage': 'final',
      'admin_manager_name': 'Asha Admin',
      'is_teaching': true,
      'substitute_faculty_id': 'f1',
      'substitute_faculty_name': 'Ravi Substitute',
      'class_timing': '10:00–11:30',
      'manager_approved_by_name': 'Asha Admin',
      'manager_remark': 'Covered at the branch.',
      'reason': 'Family function at home',
    });

    expect(request.stageLabel,
        'Admin Manager approved — waiting for Super Admin final approval');
    expect(request.coverageLabel, 'Ravi Substitute · 10:00–11:30');
    expect(request.managerApprovedByName, 'Asha Admin');
    expect(request.managerRemark, 'Covered at the branch.');
  });

  test('the branch list tells automatic, picker and HR-bypass branches apart',
      () {
    final branches = _approvers.branches;
    expect(branches[0].hasOneAdminManager, isTrue);
    expect(branches[0].effectiveManagerName, 'Asha Admin');
    expect(branches[1].hasSeveralAdminManagers, isTrue);
    expect(branches[1].effectiveManagerName, isNull);
    expect(branches[2].hasNoAdminManager, isTrue);
  });

  testWidgets('Leaves settings shows the three branch states', (tester) async {
    final repo = _MockEssRepository();
    when(() => repo.leaveApprovers()).thenAnswer((_) async => _approvers);
    getIt.registerSingleton<EssRepository>(repo);

    await tester.pumpWidget(const MaterialApp(home: LeaveApproversScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Faridabad'), findsOneWidget);
    expect(find.text('Delhi'), findsOneWidget);
    expect(find.text('Mumbai'), findsOneWidget);
    expect(find.text('Admin Manager: Asha Admin'), findsOneWidget);
    expect(find.text('HR first-stage bypass'), findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);
  });

  testWidgets('a teaching leave at the Admin Manager round asks for coverage',
      (tester) async {
    final repo = _MockEssRepository();
    when(() => repo.approvals(status: any(named: 'status')))
        .thenAnswer((_) async => const ApprovalInbox(
              attendance: 0,
              leave: 1,
              total: 1,
              requests: [_teachingLeave],
              truncated: false,
            ));
    when(() => repo.leaveFaculty(requestId: any(named: 'requestId')))
        .thenAnswer((_) async => const [
              LeaveFacultyOption(id: 'f1', name: 'Ravi Substitute'),
            ]);
    when(() => repo.decideRequest(
          family: any(named: 'family'),
          id: any(named: 'id'),
          decision: any(named: 'decision'),
          note: any(named: 'note'),
          substituteFacultyId: any(named: 'substituteFacultyId'),
          classTiming: any(named: 'classTiming'),
        )).thenAnswer((_) async => _teachingLeave);

    getIt.registerSingleton<EssRepository>(repo);
    getIt.registerFactory<ApprovalsBloc>(() => ApprovalsBloc(repo));

    await tester.pumpWidget(const MaterialApp(home: ApprovalsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Approve & send to Super Admin'), findsOneWidget);
    await tester.tap(find.text('Approve & send to Super Admin'));
    await tester.pumpAndSettle();

    expect(find.text('Coverage for teaching leave'), findsOneWidget);
    expect(find.text('Substitute faculty'), findsOneWidget);
    expect(find.text('Class timing'), findsOneWidget);

    final dialogButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Send to Super Admin'));
    await tester.tap(dialogButton);
    await tester.pumpAndSettle();
    expect(find.text('Give the class timing.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '10:00–11:30');
    await tester.tap(dialogButton);
    await tester.pumpAndSettle();

    verify(() => repo.decideRequest(
          family: 'leave',
          id: 'r1',
          decision: 'approve',
          note: null,
          substituteFacultyId: 'f1',
          classTiming: '10:00–11:30',
        )).called(1);
  });
}

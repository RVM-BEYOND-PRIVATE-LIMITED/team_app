import 'package:core_bloc/core_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/requests/approvals_screen.dart';
import 'package:rvm_team_app/features/requests/bloc/approvals_bloc.dart';
import 'package:rvm_team_app/injection.dart';

/// Issue #11: the ESS now fences a manager's status query to their own
/// reports, so the app must show every status pill to a manager too.
class _MockApprovalsBloc extends Mock implements ApprovalsBloc {}

class _MockCapabilitiesBloc extends Mock implements LoadBloc<EssCapabilities> {}

const _caps = EssCapabilities(
  tabs: ['home', 'inbox', 'wall', 'team', 'me'],
  sectionTime: true,
  sectionHelpdesk: true,
  sectionDocuments: true,
  sectionProfile: true,
  sectionWork: true,
  hasReports: true,
  directReports: 3,
  approvalsOwnReports: true,
  approvalsAnyRequest: false, // a plain manager, not HR/CEO
  approvalRequestTypes: ['on_duty', 'leave_cl'],
  hrScope: [],
  wallPost: true,
  wallAnnounce: false,
  wallModerate: false,
  pushEnabled: true,
  integrityRequired: false,
);

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  testWidgets('a manager sees the approved, rejected and all filters',
      (tester) async {
    final approvals = _MockApprovalsBloc();
    when(() => approvals.state).thenReturn(const ApprovalsState(
      status: LoadStatus.success,
      filter: 'pending',
      inbox: ApprovalInbox(requests: [], truncated: false),
    ));
    when(() => approvals.stream)
        .thenAnswer((_) => const Stream<ApprovalsState>.empty());
    when(() => approvals.close()).thenAnswer((_) async {});
    final caps = _MockCapabilitiesBloc();
    when(() => caps.state).thenReturn(const LoadState<EssCapabilities>(
        status: LoadStatus.success, data: _caps));
    when(() => caps.stream)
        .thenAnswer((_) => const Stream<LoadState<EssCapabilities>>.empty());
    when(() => caps.close()).thenAnswer((_) async {});

    getIt.registerFactory<ApprovalsBloc>(() => approvals);
    getIt.registerFactory<CapabilitiesBloc>(() => caps);

    await tester.pumpWidget(const MaterialApp(home: ApprovalsScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Pending'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
  });
}

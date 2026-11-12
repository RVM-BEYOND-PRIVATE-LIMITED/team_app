import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/hr/request_limits_screen.dart';
import 'package:rvm_team_app/features/requests/approvals_screen.dart';
import 'package:rvm_team_app/features/requests/bloc/approvals_bloc.dart';
import 'package:rvm_team_app/features/requests/bloc/request_failure.dart';
import 'package:rvm_team_app/features/requests/bloc/requests_bloc.dart';
import 'package:rvm_team_app/features/requests/raise_request_sheet.dart';
import 'package:rvm_team_app/injection.dart';

/// Issue #44: excuse-late and short-leave requests were switched off on
/// 12 Nov 2026. They are not offered any more, a pending one can only be
/// rejected or withdrawn, and the server's REQUEST_TYPE_SWITCHED_OFF refusal
/// reads as one fixed line.
class _MockApprovalsBloc extends Mock implements ApprovalsBloc {}

class _MockCapabilitiesBloc extends Mock implements LoadBloc<EssCapabilities> {}

class _MockRequestsBloc extends Mock implements RequestsBloc {}

class _MockEssRepository extends Mock implements EssRepository {}

const _caps = EssCapabilities(
  tabs: ['home', 'inbox', 'wall', 'team', 'me'],
  sectionTime: true,
  sectionHelpdesk: true,
  sectionDocuments: true,
  sectionProfile: true,
  sectionWork: false,
  hasReports: true,
  directReports: 2,
  approvalsOwnReports: true,
  approvalsAnyRequest: false,
  approvalRequestTypes: ['on_duty', 'fix_a_day'],
  hrScope: [],
  wallPost: true,
  wallAnnounce: false,
  wallModerate: false,
  pushEnabled: true,
  integrityRequired: false,
);

EssRequest _pending(String id, String type) => EssRequest.fromJson({
      'id': id,
      'family': 'attendance',
      'type': type,
      'status': 'pending',
      'day': '2026-11-10',
      'reason': 'Traffic',
      'employee': {'id': 'e-$id', 'name': 'Asha $id'},
    });

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  group('model', () {
    test('excuse-late and short leave are the switched-off types', () {
      expect(_pending('1', 'excuse_late').isSwitchedOffType, isTrue);
      expect(_pending('2', 'short_leave').isSwitchedOffType, isTrue);
      for (final t in ['on_duty', 'fix_a_day', 'cl', 'lwp']) {
        expect(_pending('3', t).isSwitchedOffType, isFalse, reason: t);
      }
      expect(const RequestLimit(type: 'short_leave').isSwitchedOff, isTrue);
      expect(const RequestLimit(type: 'fix_a_day').isSwitchedOff, isFalse);
    });
  });

  group('server refusal', () {
    test('REQUEST_TYPE_SWITCHED_OFF reads as the fixed line', () {
      final shown = requestFailure(const BadResponseFailure(
          'request type excuse_late is switched off',
          statusCode: 409,
          code: 'REQUEST_TYPE_SWITCHED_OFF'));
      expect(shown.message,
          'Excuse-late and short leave requests are switched off.');
      expect(shown.code, 'REQUEST_TYPE_SWITCHED_OFF');
      expect(shown.statusCode, 409);
    });

    test('any other refusal keeps the server message', () {
      const other = BadResponseFailure('Duplicate request.',
          statusCode: 409, code: 'DUPLICATE_REQUEST');
      expect(identical(requestFailure(other), other), isTrue);
    });
  });

  testWidgets('raise sheet no longer offers Excuse a late or Short leave',
      (tester) async {
    final bloc = _MockRequestsBloc();
    when(() => bloc.state)
        .thenReturn(const RequestsState(status: LoadStatus.success));
    when(() => bloc.stream)
        .thenAnswer((_) => const Stream<RequestsState>.empty());
    when(() => bloc.close()).thenAnswer((_) async {});

    await tester.pumpWidget(MaterialApp(
      home: BlocProvider<RequestsBloc>.value(
        value: bloc,
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showRaiseRequestSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('On duty'), findsWidgets);
    expect(find.text('Fix a day'), findsWidgets);
    expect(find.text('Excuse a late'), findsNothing);
    expect(find.text('Short leave'), findsNothing);
    expect(find.textContaining('Minutes'), findsNothing);
  });

  testWidgets(
      'a pending excuse-late can only be rejected; on duty can still be approved',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final approvals = _MockApprovalsBloc();
    when(() => approvals.state).thenReturn(ApprovalsState(
      status: LoadStatus.success,
      filter: 'pending',
      inbox: ApprovalInbox(
        attendance: 2,
        total: 2,
        requests: [_pending('1', 'excuse_late'), _pending('2', 'on_duty')],
        truncated: false,
      ),
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
    expect(
        find.text(
            'Excuse-late and short leave requests are switched off. Reject this one with a short note.'),
        findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNWidgets(2));
    // Only the on-duty request still has an Approve button.
    expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
  });

  testWidgets('HR request limits show the switched-off types without an edit',
      (tester) async {
    final repo = _MockEssRepository();
    when(() => repo.requestLimits()).thenAnswer((_) async => const [
          RequestLimit(type: 'fix_a_day', limitCount: 3),
          RequestLimit(type: 'excuse_late', limitCount: 0),
          RequestLimit(type: 'short_leave', limitMinutes: 0),
        ]);
    getIt.registerSingleton<EssRepository>(repo);

    await tester.pumpWidget(const MaterialApp(home: RequestLimitsScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Switched off'), findsNWidgets(2));
    expect(find.text('Switched off on 12 Nov 2026'), findsNWidgets(2));
    // Fix a day keeps its edit button; the switched-off rows have none.
    expect(find.byTooltip('Edit'), findsOneWidget);
  });
}

import 'package:bloc_test/bloc_test.dart';
import 'package:core_auth/core_auth.dart';
import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/connectivity_bloc.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/data/repositories/auth_repository.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/domain/models.dart';
import 'package:rvm_team_app/features/attendance/bloc/punch_bloc.dart';
import 'package:rvm_team_app/features/home/home_screen.dart';
import 'package:rvm_team_app/features/me/me_screen.dart';
import 'package:rvm_team_app/features/shell/team_shell.dart';
import 'package:rvm_team_app/injection.dart';

/// team_app #50, item 4: a sales_executive login is admitted, and the cards the
/// Scheduler's sales workspace refuses (403 SALES_WORKSPACE_ONLY) are neither
/// shown nor requested: the Inbox tab, the Interviews card and tile, and the
/// branch announcements. Every other role's screens stay as they were.
class _MockTeamAuthBloc extends MockBloc<TeamAuthEvent, TeamAuthState>
    implements TeamAuthBloc {}

class _MockPunchBloc extends MockBloc<PunchEvent, PunchState>
    implements PunchBloc {}

class _MockConnectivityBloc
    extends MockBloc<ConnectivityEvent, ConnectivityState>
    implements ConnectivityBloc {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAuthSession extends Mock implements AuthSession {}

class _MockEssRepository extends Mock implements EssRepository {}

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

StaffIdentity _identity(AppRole role) => StaffIdentity(
      userId: 'u-test',
      role: role,
      username: 'Test ${appRoleLabel(role)}',
      locationName: 'Test Branch',
    );

/// What the Home cards read, counted, so a test can see a refused read is
/// never made.
class _Reads {
  int interviews = 0;
  int announcements = 0;
  int priorityTasks = 0;
}

void _registerHome(_Reads reads) {
  getIt
    ..registerFactory<PunchBloc>(() {
      final punch = _MockPunchBloc();
      when(() => punch.state).thenReturn(const PunchState());
      return punch;
    })
    ..registerFactory<LoadBloc<TeamOffWeek>>(
        () => LoadBloc<TeamOffWeek>(() async => throw const UnknownFailure()))
    ..registerFactory<ApprovalsSummaryBloc>(() =>
        LoadBloc<ApprovalsSummary>(() async => throw const UnknownFailure()))
    ..registerFactory<InterviewsBloc>(
        () => LoadBloc<List<InterviewRound>>(() async {
              reads.interviews++;
              return const [];
            }, isEmpty: (l) => l.isEmpty))
    ..registerFactory<HomeAnnouncementsBloc>(
        () => LoadBloc<List<TeamAnnouncement>>(() async {
              reads.announcements++;
              return const [];
            }, isEmpty: (l) => l.isEmpty))
    ..registerFactory<InboxBloc>(() => LoadBloc<PriorityInbox>(() async {
          reads.priorityTasks++;
          return const PriorityInbox(tasks: []);
        }));
}

void main() {
  late _MockTeamAuthBloc auth;
  late _MockConnectivityBloc connectivity;
  late LoadBloc<EssCapabilities> caps;

  setUp(() async {
    await getIt.reset();
    auth = _MockTeamAuthBloc();
    connectivity = _MockConnectivityBloc();
    when(() => connectivity.state)
        .thenReturn(const ConnectivityState(online: true));
    caps = LoadBloc<EssCapabilities>(() async => _caps)
      ..add(const LoadSucceeded(_caps));
  });

  tearDown(() async {
    await caps.close();
    await getIt.reset();
  });

  void signedInAs(AppRole role) =>
      when(() => auth.state).thenReturn(TeamAuthState(
          status: TeamAuthStatus.authenticated, identity: _identity(role)));

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiBlocProvider(
      providers: [
        BlocProvider<TeamAuthBloc>.value(value: auth),
        BlocProvider<ConnectivityBloc>.value(value: connectivity),
        BlocProvider<CapabilitiesBloc>.value(value: caps),
      ],
      child: MaterialApp(
          theme: RvmTheme.light(seed: RvmColors.clay), home: screen),
    ));
    await tester.pumpAndSettle();
  }

  group('sign-in', () {
    test('a sales_executive login is admitted, not refused', () async {
      final repo = _MockAuthRepository();
      final session = _MockAuthSession();
      final ess = _MockEssRepository();
      when(() => session.sessionExpired)
          .thenAnswer((_) => const Stream<void>.empty());
      when(() => session.clearEssSession()).thenAnswer((_) async {});
      when(() => session.saveSchedulerSession(
          token: any(named: 'token'),
          role: any(named: 'role'))).thenAnswer((_) async {});
      when(() => ess.keepSignInSafe(deviceLabel: any(named: 'deviceLabel')))
          .thenAnswer((_) async => true);
      when(() => repo.loginSafe(
            username: any(named: 'username'),
            password: any(named: 'password'),
            locationName: any(named: 'locationName'),
          )).thenAnswer((_) async => (
            outcome: TeamSignedIn(
              token: 'header.payload.sig',
              identity: StaffIdentity.fromLoginUser({
                'userId': 'u-sales',
                'role': 'sales_executive',
                'username': 'test.sales',
              }),
            ),
            failure: null,
          ));
      final bloc = TeamAuthBloc(repository: repo, session: session, ess: ess);
      addTearDown(bloc.close);

      final settled = bloc.stream.firstWhere((s) =>
          s.status == TeamAuthStatus.authenticated || s.errorMessage != null);
      bloc.add(const TeamLoginSubmitted(
          username: 'test.sales',
          password: 'test-password',
          locationName: 'Test Branch'));
      final state = await settled;

      expect(state.errorMessage, isNull);
      expect(state.status, TeamAuthStatus.authenticated);
      expect(state.identity?.role, AppRole.salesExecutive);
      verify(() => session.saveSchedulerSession(
          token: 'header.payload.sig', role: 'sales_executive')).called(1);
    });
  });

  group('Home', () {
    testWidgets('sales: no Interviews card, no announcements, neither read',
        (tester) async {
      final reads = _Reads();
      _registerHome(reads);
      signedInAs(AppRole.salesExecutive);
      await pump(tester, const HomeScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('SALES EXECUTIVE'), findsOneWidget);
      expect(find.text('Quick actions'), findsOneWidget);
      expect(find.text('Work from home'), findsOneWidget);
      expect(find.text('Announcements'), findsNothing);
      expect(reads.interviews, 0);
      expect(reads.announcements, 0);
      expect(reads.priorityTasks, 0);
    });

    testWidgets('admin: unchanged, with interviews and announcements',
        (tester) async {
      final reads = _Reads();
      _registerHome(reads);
      signedInAs(AppRole.admin);
      await pump(tester, const HomeScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('Announcements'), findsOneWidget);
      expect(find.text('Priority tasks'), findsOneWidget);
      expect(reads.interviews, 1);
      expect(reads.announcements, 1);
      expect(reads.priorityTasks, 1);
    });
  });

  group('Me', () {
    void registerMe(AppRole role) => getIt.registerFactory<MeBloc>(() =>
        LoadBloc<TeamProfile>(() async => TeamProfile(
            id: 'u-test',
            username: 'Test ${appRoleLabel(role)}',
            role: appRoleWire(role)!)));

    testWidgets('sales: no Interviews tile and no empty Work section',
        (tester) async {
      registerMe(AppRole.salesExecutive);
      signedInAs(AppRole.salesExecutive);
      await pump(tester, const MeScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('SALES EXECUTIVE'), findsOneWidget);
      expect(find.text('ME'), findsOneWidget);
      expect(find.text('WORK'), findsNothing);
      expect(find.text('Interviews'), findsNothing);
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('Security activity'), findsOneWidget);
      expect(find.text('Helpdesk'), findsOneWidget);
    });

    testWidgets('admin: the Work section and its Interviews tile stay',
        (tester) async {
      registerMe(AppRole.admin);
      signedInAs(AppRole.admin);
      await pump(tester, const MeScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('WORK'), findsOneWidget);
      expect(find.text('Interviews'), findsOneWidget);
    });
  });

  group('the shell', () {
    Future<void> pumpShell(WidgetTester tester, AppRole role) async {
      _registerHome(_Reads());
      final ess = _MockEssRepository();
      when(() => ess.capabilitiesSafe())
          .thenAnswer((_) async => (data: _caps, failure: null));
      getIt
        ..registerSingleton<EssRepository>(ess)
        ..registerFactory<CapabilitiesBloc>(
            () => LoadBloc<EssCapabilities>(() async => _caps));
      signedInAs(role);
      await pump(tester, const TeamShell());
    }

    List<String> tabLabels(WidgetTester tester) => [
          for (final label in [
            'Home',
            'Inbox',
            'Attendance',
            'Wall',
            'My Team',
            'Me'
          ])
            if (find.text(label).evaluate().isNotEmpty) label,
        ];

    testWidgets('sales: Home, Wall, My Team and Me', (tester) async {
      await pumpShell(tester, AppRole.salesExecutive);
      expect(tester.takeException(), isNull);
      expect(tabLabels(tester), ['Home', 'Wall', 'My Team', 'Me']);
    });

    testWidgets('admin: all five tabs, as before', (tester) async {
      await pumpShell(tester, AppRole.admin);
      expect(tester.takeException(), isNull);
      expect(tabLabels(tester), ['Home', 'Inbox', 'Wall', 'My Team', 'Me']);
    });
  });
}

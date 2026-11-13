import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/connectivity_bloc.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/bloc/team_modules_bloc.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/domain/models.dart';
import 'package:rvm_team_app/domain/team_modules.dart';
import 'package:rvm_team_app/features/attendance/bloc/punch_bloc.dart';
import 'package:rvm_team_app/features/shell/team_shell.dart';
import 'package:rvm_team_app/injection.dart';
import 'package:rvm_team_app/router/app_router.dart';
import 'package:rvm_team_app/router/module_guard_listeners.dart';
import 'package:rvm_team_app/router/module_routes.dart';

/// team_app #50 items 5, 7b and check 7: the router's module guard follows
/// the modules bloc and runs again by itself when the open modules change,
/// sign-out clears them, the shell asks beside the ESS capabilities and again
/// on foreground, and with no modules (or any failed reply) the app looks
/// exactly as it does today.

class _MockTeamAuthBloc extends MockBloc<TeamAuthEvent, TeamAuthState>
    implements TeamAuthBloc {}

class _MockPunchBloc extends MockBloc<PunchEvent, PunchState>
    implements PunchBloc {}

class _MockConnectivityBloc
    extends MockBloc<ConnectivityEvent, ConnectivityState>
    implements ConnectivityBloc {}

class _MockEssRepository extends Mock implements EssRepository {}

const _prefixes = [
  '/crm',
  '/fees',
  '/ops',
  '/desk',
  '/placement',
  '/scorecards',
  '/tasks',
  '/social',
  '/complaints',
  '/moderation',
];

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

TeamAuthState _signedIn({bool attendance = false}) => TeamAuthState(
      status: TeamAuthStatus.authenticated,
      identity: StaffIdentity(
        userId: 'u-test',
        role: attendance ? AppRole.unknown : AppRole.admin,
        username: 'Test Admin',
        locationName: 'Test Branch',
        attendance: attendance,
      ),
    );

final _open = TeamModules({TeamModule.crm: false, TeamModule.tasks: true});

/// The app going to the background or coming back, as the platform says it.
Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {});
  await tester.pump();
}

void main() {
  group('the router follows the modules bloc (item 7b)', () {
    late _MockTeamAuthBloc auth;

    setUp(() async {
      await getIt.reset();
      auth = _MockTeamAuthBloc();
      when(() => auth.state).thenReturn(_signedIn());
      // /home is the shell; keep it on its access check so no tab is built.
      final ess = _MockEssRepository();
      when(() => ess.capabilitiesSafe()).thenAnswer((_) =>
          Completer<({EssCapabilities? data, Failure? failure})>().future);
      getIt
        ..registerSingleton<EssRepository>(ess)
        ..registerFactory<CapabilitiesBloc>(
            () => CapabilitiesBloc(() async => throw const UnknownFailure()));
    });
    tearDown(getIt.reset);

    Future<String> open(
        WidgetTester tester, GoRouter router, String location) async {
      router.go(location);
      await tester.pump();
      await tester.pump();
      return router.routerDelegate.currentConfiguration.uri.toString();
    }

    /// The router as main.dart builds it: the guard reads the bloc's state,
    /// and [moduleGuardListeners] sit above it.
    Future<GoRouter> pumpRouter(
        WidgetTester tester, TeamModulesBloc modules) async {
      final router =
          createRouter(auth, modules: () => modules.state.modules.open);
      await tester.pumpWidget(BlocProvider<TeamAuthBloc>.value(
        value: auth,
        child: MultiBlocListener(
          listeners: moduleGuardListeners(router: router, modules: modules),
          child: MaterialApp.router(routerConfig: router),
        ),
      ));
      await tester.pump();
      return router;
    }

    String here(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.toString();

    Future<void> answer(WidgetTester tester, TeamModulesBloc bloc,
        TeamModulesEvent event) async {
      bloc.add(event);
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(bloc.state.status, TeamModulesStatus.ready);
    }

    testWidgets('before the first answer nothing is open', (tester) async {
      final bloc = TeamModulesBloc(() async => _open);
      addTearDown(bloc.close);
      final router = await pumpRouter(tester, bloc);
      for (final prefix in _prefixes) {
        expect(await open(tester, router, prefix), '/home', reason: prefix);
        expect(await open(tester, router, '$prefix/item/1'), '/home',
            reason: prefix);
      }
    });

    testWidgets('an open module passes, the others still go home',
        (tester) async {
      final bloc = TeamModulesBloc(() async => _open);
      addTearDown(bloc.close);
      final router = await pumpRouter(tester, bloc);
      await answer(tester, bloc, const TeamModulesLoadRequested());

      // No module screen exists yet, so an open route reaches the router's
      // not-found page instead of being sent home.
      expect(await open(tester, router, '/crm'), '/crm');
      expect(find.text('Route not found: /crm'), findsOneWidget);
      expect(await open(tester, router, '/tasks/42'), '/tasks/42');
      for (final prefix
          in _prefixes.where((p) => p != '/crm' && p != '/tasks')) {
        expect(await open(tester, router, prefix), '/home', reason: prefix);
      }
      // Routes that are not modules are untouched.
      for (final location in [
        '/work/not-a-screen',
        '/hr/not-a-screen',
        '/me/not-a-screen',
      ]) {
        expect(await open(tester, router, location), location);
      }
    });

    testWidgets('a reply that fails opens nothing', (tester) async {
      final bloc = TeamModulesBloc(() async => throw const ServerFailure());
      addTearDown(bloc.close);
      final router = await pumpRouter(tester, bloc);
      await answer(tester, bloc, const TeamModulesLoadRequested());

      expect(bloc.state.modules, TeamModules.none);
      for (final prefix in _prefixes) {
        expect(await open(tester, router, prefix), '/home', reason: prefix);
      }
    });

    testWidgets(
        'a module closed by a failed refresh: the open route on screen goes '
        'home by itself', (tester) async {
      final answers = <Future<TeamModules> Function()>[
        () async => _open,
        () async => throw const TimeoutFailure(),
      ];
      final bloc = TeamModulesBloc(() => answers.removeAt(0)());
      addTearDown(bloc.close);
      final router = await pumpRouter(tester, bloc);
      await answer(tester, bloc, const TeamModulesLoadRequested());
      expect(await open(tester, router, '/crm'), '/crm');

      // No router.refresh() here: moduleGuardListeners runs the guard.
      await answer(tester, bloc, const TeamModulesRefreshRequested());
      await tester.pump();
      expect(here(router), '/home');
    });

    testWidgets('a module opened by a refresh can be reached at once',
        (tester) async {
      final answers = <Future<TeamModules> Function()>[
        () async => TeamModules.none,
        () async => _open,
      ];
      final bloc = TeamModulesBloc(() => answers.removeAt(0)());
      addTearDown(bloc.close);
      final router = await pumpRouter(tester, bloc);
      await answer(tester, bloc, const TeamModulesLoadRequested());
      expect(await open(tester, router, '/tasks'), '/home');

      await answer(tester, bloc, const TeamModulesRefreshRequested());
      expect(await open(tester, router, '/tasks'), '/tasks');
    });

    testWidgets('after sign-out nothing is open', (tester) async {
      final bloc = TeamModulesBloc(() async => _open);
      addTearDown(bloc.close);
      final router = await pumpRouter(tester, bloc);
      await answer(tester, bloc, const TeamModulesLoadRequested());
      expect(await open(tester, router, '/crm'), '/crm');

      bloc.add(const TeamModulesCleared());
      await tester.pump();
      expect(bloc.state, const TeamModulesState());
      expect(await open(tester, router, '/crm'), '/home');
    });

    testWidgets('signing out clears the modules (main.dart\'s listeners)',
        (tester) async {
      final states = StreamController<TeamAuthState>();
      addTearDown(states.close);
      whenListen(auth, states.stream, initialState: _signedIn());
      final bloc = TeamModulesBloc(() async => _open);
      addTearDown(bloc.close);
      // A bare router: this checks the listeners, not the sign-in screen.
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
      ]);
      await tester.pumpWidget(BlocProvider<TeamAuthBloc>.value(
        value: auth,
        child: MultiBlocListener(
          listeners: moduleGuardListeners(router: router, modules: bloc),
          child: MaterialApp.router(routerConfig: router),
        ),
      ));
      await answer(tester, bloc, const TeamModulesLoadRequested());
      expect(bloc.state.modules, _open);

      states.add(const TeamAuthState(status: TeamAuthStatus.unauthenticated));
      await tester.pump();
      await tester.pump();
      expect(bloc.state, const TeamModulesState());

      // The next sign-in starts from nothing open, until its own answer.
      states.add(_signedIn());
      await tester.pump();
      expect(bloc.state, const TeamModulesState());
    });
  });

  group('the shell looks the same (check 7)', () {
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
      final ess = _MockEssRepository();
      when(() => ess.capabilitiesSafe())
          .thenAnswer((_) async => (data: _caps, failure: null));
      getIt
        ..registerSingleton<EssRepository>(ess)
        ..registerFactory<CapabilitiesBloc>(
            () => LoadBloc<EssCapabilities>(() async => _caps))
        ..registerFactory<PunchBloc>(() {
          final punch = _MockPunchBloc();
          when(() => punch.state).thenReturn(const PunchState());
          return punch;
        })
        ..registerFactory<LoadBloc<TeamOffWeek>>(() =>
            LoadBloc<TeamOffWeek>(() async => throw const UnknownFailure()))
        ..registerFactory<ApprovalsSummaryBloc>(() =>
            LoadBloc<ApprovalsSummary>(
                () async => throw const UnknownFailure()))
        ..registerFactory<InterviewsBloc>(() => LoadBloc<List<InterviewRound>>(
            () async => const [],
            isEmpty: (l) => l.isEmpty))
        ..registerFactory<HomeAnnouncementsBloc>(() =>
            LoadBloc<List<TeamAnnouncement>>(() async => const [],
                isEmpty: (l) => l.isEmpty))
        ..registerFactory<InboxBloc>(() => LoadBloc<PriorityInbox>(
            () async => const PriorityInbox(tasks: [])));
    });

    tearDown(() async {
      await caps.close();
      await getIt.reset();
    });

    Future<void> pumpShell(WidgetTester tester,
        {bool attendance = false}) async {
      when(() => auth.state).thenReturn(_signedIn(attendance: attendance));
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
            theme: RvmTheme.light(seed: RvmColors.clay),
            home: const TeamShell()),
      ));
      await tester.pumpAndSettle();
    }

    /// Every text and icon on screen, in order: what the person sees.
    List<String> looks(WidgetTester tester) => [
          for (final e in find.byType(Text).evaluate())
            (e.widget as Text).data ??
                (e.widget as Text).textSpan?.toPlainText() ??
                '',
          for (final e in find.byType(Icon).evaluate())
            '${(e.widget as Icon).icon}',
        ];

    /// A modules bloc as injection.dart registers it, counting its asks. It is
    /// closed after the test (awaiting `close` inside a widget test's fake
    /// clock never returns).
    ({TeamModulesBloc bloc, List<int> asks}) registerModules(
        Future<TeamModules> Function() load) {
      final asks = <int>[];
      final bloc = TeamModulesBloc(() {
        asks.add(asks.length + 1);
        return load();
      });
      addTearDown(bloc.close);
      getIt.registerSingleton<TeamModulesBloc>(bloc);
      return (bloc: bloc, asks: asks);
    }

    /// Replies still on their way. Each is answered at the end of its test,
    /// inside the fake clock: a bloc whose handler is still waiting never
    /// finishes closing in a widget test's tear-down.
    final pending = <Completer<TeamModules>>[];

    final replies = <String, Future<TeamModules> Function()>{
      'no modules': () async => TeamModules.none,
      'every switch off (empty list)': () async => TeamModules.fromJson(
          const {'features': <Object?>[]}),
      'a failed reply': () async => throw const ServerFailure(),
      'a reply still on its way': () {
        final reply = Completer<TeamModules>();
        pending.add(reply);
        return reply.future;
      },
      // No module screen exists yet (item 6b), so an open module adds no tab
      // and no tile: nothing to tap that leads nowhere.
      'open modules': () async => _open,
    };

    for (final reply in replies.entries) {
      testWidgets('${reply.key}: the shell looks exactly as it does today',
          (tester) async {
        // Today: the shell with no modules bloc at all.
        await pumpShell(tester);
        expect(tester.takeException(), isNull);
        final today = looks(tester);
        expect(today, containsAll(['Home', 'Inbox', 'Wall', 'My Team', 'Me']));
        await tester.pumpWidget(const SizedBox());

        final modules = registerModules(reply.value);
        await pumpShell(tester);

        expect(tester.takeException(), isNull);
        expect(looks(tester), today);
        // Asked once, beside the capabilities.
        expect(modules.asks, [1]);

        for (final reply in pending) {
          reply.complete(TeamModules.none);
        }
        pending.clear();
        await tester.pump();
      });
    }

    testWidgets('asks again when the app comes back to the foreground',
        (tester) async {
      await _lifecycle(tester, AppLifecycleState.resumed);
      final modules = registerModules(() async => _open);
      await pumpShell(tester);
      expect(modules.asks, [1]);

      await _lifecycle(tester, AppLifecycleState.paused);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(modules.asks, [1, 2]);
      expect(modules.bloc.state.modules, _open);
    });

    testWidgets('an attendance-only sign-in asks nothing', (tester) async {
      await _lifecycle(tester, AppLifecycleState.resumed);
      final modules = registerModules(() async => _open);
      await pumpShell(tester, attendance: true);
      expect(tester.takeException(), isNull);

      await _lifecycle(tester, AppLifecycleState.paused);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(modules.asks, isEmpty);
      expect(modules.bloc.state, const TeamModulesState());
    });

    testWidgets('a refused capabilities check asks nothing', (tester) async {
      final ess = getIt<EssRepository>();
      when(() => (ess as _MockEssRepository).capabilitiesSafe()).thenAnswer(
          (_) async => (data: null, failure: const ForbiddenFailure()));
      final modules = registerModules(() async => _open);
      await pumpShell(tester);

      expect(find.text('Try again'), findsOneWidget);
      expect(modules.asks, isEmpty);
      expect(modules.bloc.state.modules, TeamModules.none);
    });
  });
}

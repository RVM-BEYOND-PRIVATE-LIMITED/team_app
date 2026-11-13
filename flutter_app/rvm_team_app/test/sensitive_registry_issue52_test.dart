import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/auth/team_permissions.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/shell/tab_registry.dart';
import 'package:rvm_team_app/features/shell/tile_registry.dart';
import 'package:rvm_team_app/features/shell/team_shell.dart';
import 'package:rvm_team_app/features/work/bloc/mark_attendance_bloc.dart';
import 'package:rvm_team_app/features/work/mark_attendance_screen.dart';
import 'package:rvm_team_app/injection.dart';
import 'package:rvm_team_app/platform/secure_window.dart';
import 'package:rvm_team_app/router/app_router.dart';
import 'package:rvm_team_app/router/module_routes.dart';
import 'package:rvm_team_app/router/sensitive_routes.dart';
import 'package:rvm_team_app/widgets/secure_scope.dart';

import 'support/app_routes.dart';

/// team_app #52, item 1: each module is marked sensitive once, in the module
/// registry from #50, for the modules the issue names (CRM, fees follow-up,
/// student desk, placement checks, complaints; question 3's default). The
/// class roster is screenshot-blocked too, behind its own switch, which is off
/// unless a build passes `--dart-define=SECURE_ROSTER=true`. Home, the Wall and
/// every other screen, tab and tile are not, so their screenshots work as
/// before.
class _MockTeamAuthBloc extends Mock implements TeamAuthBloc {}

class _MockAuthBloc extends MockBloc<TeamAuthEvent, TeamAuthState>
    implements TeamAuthBloc {}

class _MockEssRepository extends Mock implements EssRepository {}

const _sensitive = {
  TeamModule.crm,
  TeamModule.fees,
  TeamModule.desk,
  TeamModule.placement,
  TeamModule.complaints,
};

EssCapabilities _caps() => const EssCapabilities(
      tabs: ['home', 'inbox', 'wall', 'team', 'me'],
      sectionTime: true,
      sectionHelpdesk: true,
      sectionDocuments: true,
      sectionProfile: true,
      sectionWork: true,
      hasReports: true,
      directReports: 1,
      approvalsOwnReports: true,
      approvalsAnyRequest: true,
      approvalRequestTypes: [],
      hrScope: ['documents'],
      wallPost: true,
      wallAnnounce: true,
      wallModerate: true,
      pushEnabled: true,
      integrityRequired: false,
    );

void main() {
  group('the registry marks', () {
    test('exactly the modules the issue names', () {
      expect({
        for (final m in TeamModule.values)
          if (m.sensitive) m
      }, _sensitive);
    });

    test('every route of a sensitive module, and the class roster', () {
      for (final module in _sensitive) {
        for (final roster in [false, true]) {
          expect(
              isSensitiveLocation(module.routePrefix, roster: roster), isTrue,
              reason: module.name);
          expect(
              isSensitiveLocation('${module.routePrefix}/leads/7',
                  roster: roster),
              isTrue,
              reason: module.name);
        }
      }
      expect(isSensitiveLocation('/work/batch/b1/mark', roster: true), isTrue);
    });

    test('the roster\'s switch is off by default', () {
      // No --dart-define=SECURE_ROSTER=true in a normal build or test run.
      expect(secureRosterOn, isFalse);
      expect(isSensitiveLocation('/work/batch/b1/mark'), isFalse);
      expect(
          isSensitiveLocation('/work/batch/b1/mark', roster: false), isFalse);
    });

    test('no other screen', () {
      for (final location in [
        '/home',
        '/wall/post/1',
        '/wall/moderation',
        '/work/batches',
        '/work/batch/b1',
        '/work/batch/b1/mark/x',
        '/work/my-day',
        '/me/id-card',
        '/me/sessions',
        '/hr/tools',
        '/notifications',
        '/ops',
        '/scorecards/1',
        '/tasks',
        '/social',
        '/moderation',
        '/crmx',
        '/',
      ]) {
        expect(isSensitiveLocation(location, roster: true), isFalse,
            reason: location);
      }
    });

    test('no tab or Me tile today, for any role or sign-in', () {
      for (final role in AppRole.values) {
        for (final attendance in [false, true]) {
          final viewer =
              TeamViewer(role: role, attendance: attendance, caps: _caps());
          for (final tab in teamTabsFor(viewer)) {
            expect(tab.sensitive, isFalse, reason: '$role ${tab.id}');
          }
          for (final section in meSectionsFor(viewer)) {
            for (final tile in section.tiles) {
              expect(tile.sensitive, isFalse, reason: '$role ${tile.id}');
            }
          }
        }
      }
      for (final section in meSectionRegistry) {
        for (final tile in section.tiles) {
          expect(tile.sensitive, isFalse, reason: tile.id);
        }
      }
    });
  });

  group('the router', () {
    late _MockTeamAuthBloc auth;
    late List<String> calls;
    const channel = MethodChannel(SecureWindow.channelName);

    setUp(() async {
      await getIt.reset();
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      auth = _MockTeamAuthBloc();
      when(() => auth.state).thenReturn(const TeamAuthState(
        status: TeamAuthStatus.authenticated,
        identity: StaffIdentity(userId: 'u-test', role: AppRole.faculty),
      ));
      // /home is the shell; keep it on its access check so no tab is built.
      final ess = _MockEssRepository();
      when(() => ess.capabilitiesSafe()).thenAnswer((_) =>
          Completer<({EssCapabilities? data, Failure? failure})>().future);
      // The roster's own load never finishes: this test is about the window.
      when(() => ess.classRoster(
              batchId: any(named: 'batchId'), date: any(named: 'date')))
          .thenAnswer((_) => Completer<ClassRoster>().future);
      getIt
        ..registerSingleton<EssRepository>(ess)
        ..registerFactory<CapabilitiesBloc>(
            () => CapabilitiesBloc(() async => throw const UnknownFailure()))
        ..registerFactoryParam<MarkAttendanceBloc, String, DateTime>(
            (batchId, date) =>
                MarkAttendanceBloc(ess, batchId: batchId, date: date));
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await getIt.reset();
    });

    Future<void> settle(WidgetTester tester) async {
      // The shell's access check spins forever, so no pumpAndSettle.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('switched off (the default), the roster screenshots as before',
        (tester) async {
      final router = createRouter(auth);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go('/home');
      await settle(tester);

      unawaited(router.push('/work/batch/b1/mark', extra: 'Test Batch'));
      await settle(tester);
      expect(find.byType(MarkAttendanceScreen), findsOneWidget);
      expect(find.byType(SecureScope), findsNothing);
      expect(calls, isEmpty);

      router.pop();
      await settle(tester);
      expect(calls, isEmpty);
    });

    testWidgets(
        'switched on, the class roster blocks screenshots; Home does not',
        (tester) async {
      final router = createRouter(auth, secureRoster: true);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go('/home');
      await settle(tester);
      expect(calls, isEmpty, reason: 'Home');
      expect(find.byType(SecureScope), findsNothing);

      unawaited(router.push('/work/batch/b1/mark', extra: 'Test Batch'));
      await settle(tester);
      expect(find.byType(SecureScope), findsOneWidget);
      expect(calls, ['enable']);

      router.pop();
      await settle(tester);
      expect(calls, ['enable', 'disable']);
      expect(SecureWindow.instance.isOn, isFalse);
    });

    testWidgets('a screen that is not sensitive has no SecureScope',
        (tester) async {
      final router = createRouter(auth);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go('/work/not-a-screen');
      await settle(tester);

      expect(find.byType(SecureScope), findsNothing);
      expect(calls, isEmpty);
    });
  });

  // So a future /crm, /fees, /desk, /placement or /complaints route, or a
  // sensitive tab, cannot skip the block: the router's own routes are walked
  // and built, and every sensitive one must come back under a SecureScope.
  group('every sensitive route is wrapped in SecureScope', () {
    late _MockTeamAuthBloc auth;

    setUp(() {
      auth = _MockTeamAuthBloc();
      when(() => auth.state).thenReturn(const TeamAuthState());
    });

    /// The paths among [routes] that are sensitive but whose builder does not
    /// put the screen under a SecureScope. A route with no builder (a page
    /// builder) cannot be checked, so it counts as unwrapped.
    List<String> unwrapped(List<BuiltRoute> routes, {required bool roster}) => [
          for (final r in routes)
            if (isSensitiveLocation(r.location, roster: roster) &&
                r.screen is! SecureScope)
              r.path,
        ];

    Future<List<BuiltRoute>> routesOf(
        WidgetTester tester, GoRouter router) async {
      addTearDown(router.dispose);
      late BuildContext context;
      await tester.pumpWidget(Builder(builder: (c) {
        context = c;
        return const SizedBox.shrink();
      }));
      return builtRoutes(router, context);
    }

    testWidgets('every sensitive module route, and the roster switched on',
        (tester) async {
      final routes =
          await routesOf(tester, createRouter(auth, secureRoster: true));

      expect(routes.map((r) => r.path), contains('/work/batch/:id/mark'),
          reason: 'the walk reaches the router\'s routes');
      expect(unwrapped(routes, roster: true), isEmpty);
      for (final r in routes) {
        expect(r.screen is SecureScope,
            isSensitiveLocation(r.location, roster: true),
            reason: r.path);
      }
    });

    testWidgets('switched off, only a sensitive module\'s routes are wrapped',
        (tester) async {
      final routes = await routesOf(tester, createRouter(auth));

      expect(unwrapped(routes, roster: false), isEmpty);
      for (final r in routes) {
        expect(r.screen is SecureScope,
            isSensitiveLocation(r.location, roster: false),
            reason: r.path);
      }
      final roster =
          routes.singleWhere((r) => r.path == '/work/batch/:id/mark');
      expect(roster.screen, isA<MarkAttendanceScreen>());
    });

    testWidgets('the check catches a module route that skips it',
        (tester) async {
      Widget plain(BuildContext _, GoRouterState __) => const SizedBox.shrink();
      Widget wrapped(BuildContext _, GoRouterState __) =>
          const SecureScope(child: SizedBox.shrink());
      final router = GoRouter(routes: [
        GoRoute(path: '/home', builder: plain),
        GoRoute(path: '/crm', builder: wrapped, routes: [
          GoRoute(path: 'leads/:id', builder: plain),
        ]),
        GoRoute(path: '/fees/:id', builder: plain),
        GoRoute(
            path: '/desk',
            pageBuilder: (_, __) => const NoTransitionPage<void>(
                child: SecureScope(child: SizedBox.shrink()))),
        ShellRoute(builder: (_, __, child) => child, routes: [
          GoRoute(path: '/complaints/open', builder: plain),
          GoRoute(path: '/placement', builder: wrapped),
        ]),
        GoRoute(path: '/ops', builder: plain),
        GoRoute(path: '/work/batch/:id/mark', builder: plain),
      ]);

      final routes = await routesOf(tester, router);

      expect(unwrapped(routes, roster: false),
          ['/crm/leads/:id', '/fees/:id', '/desk', '/complaints/open']);
      expect(unwrapped(routes, roster: true), [
        '/crm/leads/:id',
        '/fees/:id',
        '/desk',
        '/complaints/open',
        '/work/batch/:id/mark',
      ]);
    });
  });

  group('the shell', () {
    late List<String> calls;
    late List<TeamTabSpec> saved;
    const channel = MethodChannel(SecureWindow.channelName);
    const allTabs = EssCapabilities(
      tabs: [],
      sectionTime: true,
      sectionHelpdesk: true,
      sectionDocuments: true,
      sectionProfile: true,
      sectionWork: true,
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

    TeamTabSpec spec(String id, {bool sensitive = false}) => TeamTabSpec(
          id: id,
          visible: (_) => true,
          tab: (_) => TeamTab(
            id: id,
            label: id,
            icon: Icons.circle_outlined,
            selectedIcon: Icons.circle,
            body: Text('$id body'),
            sensitive: sensitive,
          ),
        );

    setUp(() async {
      await getIt.reset();
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      // The shell draws what the registry holds: one sensitive tab among
      // ordinary ones stands in for a future dialer or desk tab.
      saved = [...teamTabRegistry];
      teamTabRegistry
        ..clear()
        ..addAll([spec('home'), spec('dialer', sensitive: true), spec('wall')]);
      final ess = _MockEssRepository();
      when(() => ess.capabilitiesSafe())
          .thenAnswer((_) async => (data: allTabs, failure: null));
      getIt
        ..registerSingleton<EssRepository>(ess)
        ..registerFactory<CapabilitiesBloc>(
            () => CapabilitiesBloc(() async => allTabs));
    });

    tearDown(() async {
      teamTabRegistry
        ..clear()
        ..addAll(saved);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await getIt.reset();
    });

    /// The SecureScope around [text], on screen or built off it in the stack.
    Finder scopeAround(String text) => find.ancestor(
        of: find.text(text, skipOffstage: false),
        matching: find.byType(SecureScope, skipOffstage: false));

    testWidgets('wraps every sensitive tab, and holds it only while selected',
        (tester) async {
      final auth = _MockAuthBloc();
      when(() => auth.state).thenReturn(const TeamAuthState(
        status: TeamAuthStatus.authenticated,
        identity: StaffIdentity(userId: 'u-test', role: AppRole.faculty),
      ));
      await tester.pumpWidget(BlocProvider<TeamAuthBloc>.value(
          value: auth, child: const MaterialApp(home: TeamShell())));
      await tester.pump();
      await tester.pump();
      expect(find.text('home body'), findsOneWidget);
      expect(calls, isEmpty, reason: 'Home');

      await tester.tap(find.text('dialer'));
      await tester.pump();
      expect(scopeAround('dialer body'), findsOneWidget);
      expect(calls, ['enable']);

      await tester.tap(find.text('wall'));
      await tester.pump();
      expect(calls, ['enable', 'disable'],
          reason: 'the dialer stays built in the stack, but off screen');
      expect(scopeAround('home body'), findsNothing);
      expect(scopeAround('wall body'), findsNothing);
      expect(scopeAround('dialer body'), findsOneWidget);
      expect(SecureWindow.instance.isOn, isFalse);
    });
  });
}

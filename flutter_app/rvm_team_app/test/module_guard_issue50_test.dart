import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/injection.dart';
import 'package:rvm_team_app/router/app_router.dart';
import 'package:rvm_team_app/router/module_routes.dart';

/// team_app #50, item 7: one route prefix per module; a module route the
/// person does not have falls back to /home, and with no modules (today, until
/// Scheduler_Backend#157 / #175) every module route does. /work, /hr and /me
/// are untouched.
class _MockTeamAuthBloc extends Mock implements TeamAuthBloc {}

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

void main() {
  group('module route prefixes', () {
    test('one prefix per module, exactly the ten the issue names', () {
      expect([for (final m in TeamModule.values) m.routePrefix], _prefixes);
      expect({for (final m in TeamModule.values) m.routePrefix},
          hasLength(TeamModule.values.length));
    });

    test('a location belongs to the module whose prefix it sits under', () {
      expect(moduleForLocation('/crm'), TeamModule.crm);
      expect(moduleForLocation('/crm/leads/7'), TeamModule.crm);
      expect(moduleForLocation('/tasks'), TeamModule.tasks);
      expect(moduleForLocation('/social/post/1'), TeamModule.social);
      expect(moduleForLocation('/moderation/queue'), TeamModule.moderation);
    });

    test('no other location is a module route', () {
      for (final location in [
        '/home',
        '/work',
        '/work/batches',
        '/work/batch/b1/mark',
        '/hr/tools',
        '/me/profile',
        '/wall/moderation', // the Wall's own moderation screen, not /moderation
        '/crmx',
        '/tasksboard',
        '/notifications',
        '/',
      ]) {
        expect(moduleForLocation(location), isNull, reason: location);
      }
    });

    test('with no modules every module route is blocked', () {
      expect(noTeamModules(), isEmpty);
      for (final prefix in _prefixes) {
        expect(moduleBlockedLocation(prefix, noTeamModules()), isTrue,
            reason: prefix);
        expect(moduleBlockedLocation('$prefix/x', noTeamModules()), isTrue,
            reason: prefix);
      }
    });

    test('a granted module opens; the others stay blocked', () {
      const granted = {TeamModule.tasks};
      expect(moduleBlockedLocation('/tasks', granted), isFalse);
      expect(moduleBlockedLocation('/tasks/42', granted), isFalse);
      expect(moduleBlockedLocation('/crm', granted), isTrue);
      expect(moduleBlockedLocation('/social', granted), isTrue);
    });
  });

  group('the router', () {
    late _MockTeamAuthBloc auth;

    setUp(() async {
      await getIt.reset();
      auth = _MockTeamAuthBloc();
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

    void signedIn({bool attendance = false}) {
      when(() => auth.state).thenReturn(TeamAuthState(
        status: TeamAuthStatus.authenticated,
        identity: StaffIdentity(
            userId: 'u-test',
            role: attendance ? AppRole.unknown : AppRole.admin,
            attendance: attendance),
      ));
    }

    Future<String> open(
        WidgetTester tester, GoRouter router, String location) async {
      router.go(location);
      await tester.pump();
      await tester.pump();
      return router.routerDelegate.currentConfiguration.uri.toString();
    }

    Future<GoRouter> pumpRouter(WidgetTester tester,
        {Set<TeamModule> Function()? modules}) async {
      final router = modules == null
          ? createRouter(auth)
          : createRouter(auth, modules: modules);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      return router;
    }

    testWidgets('sends every module route home when nobody has modules',
        (tester) async {
      signedIn();
      final router = await pumpRouter(tester);
      for (final prefix in _prefixes) {
        expect(await open(tester, router, prefix), '/home', reason: prefix);
        expect(await open(tester, router, '$prefix/item/1'), '/home',
            reason: prefix);
      }
    });

    testWidgets('lets a granted module through and blocks the rest',
        (tester) async {
      signedIn();
      final router =
          await pumpRouter(tester, modules: () => {TeamModule.tasks});
      // No module screen exists yet, so a granted route reaches the router's
      // not-found page instead of being sent home.
      expect(await open(tester, router, '/tasks'), '/tasks');
      expect(find.text('Route not found: /tasks'), findsOneWidget);
      expect(await open(tester, router, '/crm'), '/home');
    });

    testWidgets('/work, /hr and /me are not module routes', (tester) async {
      signedIn();
      final router = await pumpRouter(tester);
      for (final location in [
        '/work/not-a-screen',
        '/hr/not-a-screen',
        '/me/not-a-screen',
      ]) {
        expect(await open(tester, router, location), location,
            reason: location);
      }
    });

    testWidgets('attendance-only sign-ins keep their own guard',
        (tester) async {
      signedIn(attendance: true);
      final router = await pumpRouter(tester);
      expect(await open(tester, router, '/work/batches'), '/home');
      expect(await open(tester, router, '/social'), '/home');
      expect(
          await open(tester, router, '/me/not-a-screen'), '/me/not-a-screen');
    });
  });
}

import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/auth/team_permissions.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/shell/tab_registry.dart';
import 'package:rvm_team_app/features/shell/tile_registry.dart';
import 'package:rvm_team_app/features/work/bloc/mark_attendance_bloc.dart';
import 'package:rvm_team_app/injection.dart';
import 'package:rvm_team_app/platform/secure_window.dart';
import 'package:rvm_team_app/router/app_router.dart';
import 'package:rvm_team_app/router/module_routes.dart';
import 'package:rvm_team_app/router/sensitive_routes.dart';
import 'package:rvm_team_app/widgets/secure_scope.dart';

/// team_app #52, item 1: each module is marked sensitive once, in the module
/// registry from #50, for the modules the issue names (CRM, fees follow-up,
/// student desk, placement checks, complaints; question 3's default). The
/// class roster is screenshot-blocked too. Home, the Wall and every other
/// screen, tab and tile are not, so their screenshots work as before.
class _MockTeamAuthBloc extends Mock implements TeamAuthBloc {}

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
        expect(isSensitiveLocation(module.routePrefix), isTrue,
            reason: module.name);
        expect(isSensitiveLocation('${module.routePrefix}/leads/7'), isTrue,
            reason: module.name);
      }
      expect(isSensitiveLocation('/work/batch/b1/mark'), isTrue);
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
        expect(isSensitiveLocation(location), isFalse, reason: location);
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

    testWidgets('the class roster blocks screenshots; Home does not',
        (tester) async {
      final router = createRouter(auth);
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
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/notifications/bloc/notifications_bloc.dart';
import 'package:rvm_team_app/features/notifications/notifications_screen.dart';
import 'package:rvm_team_app/injection.dart';
import 'package:rvm_team_app/push/push_service.dart';

/// team_app #50, item 8: a tap on a notifications-list row opens the row's
/// `data.route`, and falls back to the request screens `requestRouteFor`
/// knows. A row with neither keeps today's tap: it is only marked read.
class _MockEssRepository extends Mock implements EssRepository {}

AppNotification _row(String id, String category,
        {Map<String, dynamic> data = const {}, bool read = false}) =>
    AppNotification(
      id: id,
      category: category,
      title: 'Title $id',
      body: 'Body $id',
      data: data,
      readAt: read ? DateTime.utc(2026, 11, 1) : null,
    );

void main() {
  group('notificationRowRoute', () {
    test('opens the row\'s own data.route', () {
      expect(notificationRowRoute('praise', {'route': '/wall/post/7'}),
          '/wall/post/7');
      // A link is read for its path, as a push tap reads it.
      expect(
          notificationRowRoute('helpdesk',
              {'route': 'https://team.example.test/helpdesk/ticket/3'}),
          '/helpdesk/ticket/3');
    });

    test('falls back to the request screens (the ESS rows of today)', () {
      // apps/ess-api src/lib/notify.js: data {request_id, request_family}, the
      // category on the row itself.
      expect(
          notificationRowRoute(
              'approvals', {'request_id': 'r1', 'request_family': 'leave'}),
          '/approvals');
      expect(
          notificationRowRoute('decisions',
              {'request_id': 'r1', 'request_family': 'attendance'}),
          '/requests');
    });

    test('data.route wins over the request fallback', () {
      expect(
          notificationRowRoute('approvals', {
            'route': '/requests',
            'request_id': 'r1',
            'request_family': 'leave',
          }),
          '/requests');
    });

    test('has nothing to open for other rows, or for this list itself', () {
      expect(notificationRowRoute('priority_tasks', {'task_id': 't1'}), isNull);
      expect(notificationRowRoute('praise', const {}), isNull);
      expect(notificationRowRoute('approvals', const {}), isNull);
      expect(notificationRowRoute('mentions', {'route': ''}), isNull);
      expect(notificationRowRoute('mentions', {'route': 'not a path'}), isNull);
      expect(notificationRowRoute('mentions', {'route': '/notifications'}),
          isNull);
    });
  });

  group('the notifications list', () {
    late _MockEssRepository ess;

    setUp(() async {
      await getIt.reset();
      ess = _MockEssRepository();
      when(() => ess.notifications())
          .thenAnswer((_) async => NotificationPage(notifications: [
                _row('n1', 'praise', data: {'route': '/wall/post/7'}),
                _row('n2', 'approvals',
                    data: {'request_id': 'r1', 'request_family': 'leave'},
                    read: true),
                _row('n3', 'priority_tasks', data: {'task_id': 't1'}),
                _row('n4', 'praise', read: true),
              ], unread: 2, truncated: false));
      when(() => ess.notificationSettings())
          .thenAnswer((_) async => const NotificationSettings(categories: []));
      when(() => ess.readNotification(any())).thenAnswer((_) async {});
      getIt.registerFactory<NotificationsBloc>(() => NotificationsBloc(ess));
    });
    tearDown(getIt.reset);

    Future<GoRouter> pumpList(WidgetTester tester) async {
      Widget page(String name) => Scaffold(body: Text('page $name'));
      final router = GoRouter(
        initialLocation: '/notifications',
        routes: [
          GoRoute(
              path: '/notifications',
              builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: '/approvals', builder: (_, __) => page('approvals')),
          GoRoute(path: '/requests', builder: (_, __) => page('requests')),
          GoRoute(
              path: '/wall/post/:id',
              builder: (_, s) => page('post ${s.pathParameters['id']}')),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('an unread row with a route is marked read and opened',
        (tester) async {
      final router = await pumpList(tester);
      await tester.tap(find.text('Title n1'));
      await tester.pumpAndSettle();

      expect(find.text('page post 7'), findsOneWidget);
      verify(() => ess.readNotification('n1')).called(1);
      // Pushed, so Back returns to the list.
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Title n1'), findsOneWidget);
    });

    testWidgets('a read request row opens its request screen', (tester) async {
      await pumpList(tester);
      await tester.tap(find.text('Title n2'));
      await tester.pumpAndSettle();

      expect(find.text('page approvals'), findsOneWidget);
      verifyNever(() => ess.readNotification(any()));
    });

    testWidgets('an unread row with nowhere to go is only marked read',
        (tester) async {
      final router = await pumpList(tester);
      await tester.tap(find.text('Title n3'));
      await tester.pumpAndSettle();

      verify(() => ess.readNotification('n3')).called(1);
      expect(router.routerDelegate.currentConfiguration.uri.toString(),
          '/notifications');
    });

    testWidgets('a read row with nowhere to go stays untappable, as before',
        (tester) async {
      await pumpList(tester);
      final tile = tester.widget<ListTile>(find.ancestor(
          of: find.text('Title n4'), matching: find.byType(ListTile)));
      expect(tile.onTap, isNull);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../bloc/team_auth_bloc.dart';
import '../features/attendance/punch_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/helpdesk/helpdesk_screen.dart';
import '../features/hr/hr_bank_screen.dart';
import '../features/hr/hr_change_requests_screen.dart';
import '../features/hr/hr_documents_screen.dart';
import '../features/hr/leaders_screen.dart';
import '../features/hr/request_limits_screen.dart';
import '../features/helpdesk/queue_screen.dart';
import '../features/helpdesk/ticket_screen.dart';
import '../features/hod/hod_screen.dart';
import '../features/hr/employee_personal_screen.dart';
import '../features/hr/hr_tools_screen.dart';
import '../features/me/account_security_screen.dart';
import '../features/me/attendance_day_screen.dart';
import '../features/me/bank_details_screen.dart';
import '../features/me/change_requests_screen.dart';
import '../features/me/data_requests_screen.dart';
import '../features/me/documents_screen.dart';
import '../features/me/id_card_screen.dart';
import '../features/me/profile_screen.dart';
import '../features/me/personal_details_screen.dart';
import '../features/me/security_events_screen.dart';
import '../features/me/sessions_screen.dart';
import '../features/my_team/directory_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/requests/approvals_screen.dart';
import '../features/requests/requests_screen.dart';
import '../features/wall/wall_moderation_screen.dart';
import '../features/wall/wall_post_screen.dart';
import '../features/shell/team_shell.dart';
import '../features/work/faculty_day_screen.dart';
import '../features/work/faculty_indicators_screen.dart';
import '../features/work/interviews_screen.dart';
import '../features/work/mark_attendance_screen.dart';
import '../features/work/my_batches_screen.dart';

/// Auth-gated router. Redirect reads [TeamAuthBloc] state; the app calls
/// `router.refresh()` when that state changes: splash → login → five-tab shell.
GoRouter createRouter(TeamAuthBloc authBloc,
    {GlobalKey<NavigatorState>? navigatorKey}) {
  const authOnly = {'/login', '/forgot'};
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      switch (authBloc.state.status) {
        case TeamAuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case TeamAuthStatus.unauthenticated:
          return authOnly.contains(loc) ? null : '/login';
        case TeamAuthStatus.authenticated:
          return (loc == '/splash' || authOnly.contains(loc)) ? '/home' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/forgot', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/home', builder: (_, __) => const TeamShell()),
      GoRoute(
          path: '/work/batches', builder: (_, __) => const MyBatchesScreen()),
      GoRoute(
          path: '/work/indicators',
          builder: (_, __) => const FacultyIndicatorsScreen()),
      GoRoute(path: '/work/hod', builder: (_, __) => const HodScreen()),
      GoRoute(
          path: '/work/interviews',
          builder: (_, __) => const InterviewsScreen()),
      GoRoute(
        path: '/work/batch/:id/mark',
        builder: (_, state) => MarkAttendanceScreen(
          batchId: state.pathParameters['id']!,
          batchName: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
          path: '/account/security',
          builder: (_, __) => const AccountSecurityScreen()),
      GoRoute(
          path: '/account/security-events',
          builder: (_, __) => const SecurityEventsScreen()),
      // ── Team RVM ESS (1A/1B) ────────────────────────────────────────────
      GoRoute(
          path: '/me/personal',
          builder: (_, __) => const PersonalDetailsScreen()),
      // ── Team RVM ESS (2C: documents, bank, ID card, profile changes) ───────
      GoRoute(path: '/me/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
          path: '/me/documents', builder: (_, __) => const DocumentsScreen()),
      GoRoute(path: '/me/bank', builder: (_, __) => const BankDetailsScreen()),
      GoRoute(path: '/me/id-card', builder: (_, __) => const IdCardScreen()),
      GoRoute(
          path: '/me/change-requests',
          builder: (_, __) => const ChangeRequestsScreen()),
      GoRoute(
          path: '/me/data-requests',
          builder: (_, __) => const DataRequestsScreen()),
      GoRoute(path: '/me/punch', builder: (_, __) => const PunchScreen()),
      GoRoute(
          path: '/me/attendance',
          builder: (_, __) => const AttendanceDayScreen()),
      GoRoute(path: '/me/sessions', builder: (_, __) => const SessionsScreen()),
      GoRoute(
          path: '/team/directory', builder: (_, __) => const DirectoryScreen()),
      // ── Team RVM ESS (1C: requests, leave, approvals) ─────────────────────
      GoRoute(path: '/requests', builder: (_, __) => const RequestsScreen()),
      GoRoute(path: '/approvals', builder: (_, __) => const ApprovalsScreen()),
      GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen()),
      // ── Team RVM ESS (2A: the Wall) ──────────────────────────────────────
      GoRoute(
          path: '/wall/post/:id',
          builder: (_, state) =>
              WallPostScreen(postId: state.pathParameters['id']!)),
      // ── Team RVM ESS (2B: Helpdesk) ─────────────────────────────────────
      GoRoute(path: '/helpdesk', builder: (_, __) => const HelpdeskScreen()),
      GoRoute(
          path: '/helpdesk/queue',
          builder: (_, __) => const HelpdeskQueueScreen()),
      GoRoute(
          path: '/helpdesk/ticket/:id',
          builder: (_, state) =>
              TicketScreen(ticketId: state.pathParameters['id']!)),
      GoRoute(path: '/hr/tools', builder: (_, __) => const HrToolsScreen()),
      // ── Team RVM ESS (2D) ────────────────────────────────────────────────
      GoRoute(path: '/leaders', builder: (_, __) => const LeadersScreen()),
      GoRoute(
          path: '/work/my-day', builder: (_, __) => const FacultyDayScreen()),
      // ── HR desks (2B/2C) ────────────────────────────────────────────────
      GoRoute(
          path: '/hr/request-limits',
          builder: (_, __) => const RequestLimitsScreen()),
      GoRoute(
          path: '/hr/change-requests',
          builder: (_, __) => const HrChangeRequestsScreen()),
      GoRoute(
          path: '/hr/documents', builder: (_, __) => const HrDocumentsScreen()),
      GoRoute(path: '/hr/bank', builder: (_, __) => const HrBankScreen()),
      GoRoute(
          path: '/wall/moderation',
          builder: (_, __) => const WallModerationScreen()),
      GoRoute(
        path: '/hr/employee/:id/personal',
        builder: (_, state) => EmployeePersonalScreen(
          employeeId: state.pathParameters['id']!,
          employeeName: state.extra is String ? state.extra as String : null,
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
}

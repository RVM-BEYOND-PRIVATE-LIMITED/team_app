import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../bloc/team_auth_bloc.dart';
import '../features/attendance/punch_screen.dart';
import '../features/complaints/complaints_screens.dart';
import '../features/desk/desk_screens.dart';
import '../features/marks/marks_screen.dart';
import '../features/moderation/moderation_screens.dart';
import '../features/ops/ops_screens.dart';
import '../features/placement/placement_screens.dart';
import '../features/scorecards/scorecard_screens.dart';
import '../features/security/security_screens.dart';
import '../features/security/sensitive_gate.dart';
import '../features/social/social_screens.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/crm/crm_add_lead_screen.dart';
import '../features/crm/crm_call_screen.dart';
import '../features/crm/crm_calendar_screen.dart';
import '../features/crm/crm_disposition_screen.dart';
import '../features/crm/crm_home_screen.dart';
import '../features/crm/crm_lead_screen.dart';
import '../features/crm/crm_leads_screen.dart';
import '../domain/crm_models.dart';
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
import '../features/hr/hr_wfh_allowances_screen.dart';
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
import '../widgets/secure_scope.dart';
import 'module_routes.dart';
import 'sensitive_routes.dart';

/// Locations that only a portal sign-in can use (issue #13).
///
/// An attendance-only session carries a punch token: the Scheduler's own guards
/// refuse it, and the ESS's portal-role routes refuse it too. The tiles are
/// already hidden, but a deep link or a stale history entry must not land on a
/// screen that can only draw a 401/403. Everything else (the ESS surface: Me,
/// requests, documents, Wall, Helpdesk tickets, notifications, sessions,
/// directory) stays open.
bool attendanceBlockedLocation(String location) {
  const exact = {
    '/account/security-events', // Scheduler /api/me/security-events
    '/helpdesk/queue', // ESS portal-role route (403 PORTAL_LOGIN_REQUIRED)
    '/leaders', // CEO / super admin only
  };
  if (exact.contains(location)) return true;
  // Teaching screens and the Scheduler-backed HR desks (/work/..., /hr/...).
  return location == '/work' ||
      location.startsWith('/work/') ||
      location == '/hr' ||
      location.startsWith('/hr/');
}

int? _int(Object? value) => value is String ? int.tryParse(value) : null;

CrmBucket _crmBucket(String? wire) => switch (wire) {
      'uncontacted' => CrmBucket.uncontacted,
      'in_progress' => CrmBucket.inProgress,
      'follow_up' => CrmBucket.followUp,
      'not_connected' => CrmBucket.notConnected,
      _ => CrmBucket.all,
    };

/// [screen] under a [SecureScope] when its location is sensitive
/// ([isSensitiveLocation], team_app #52 item 1), so screenshots of it come out
/// black. [roster] is the class roster's switch ([secureRosterOn]). A module's
/// screens must go through here too when they are added: the router test
/// (sensitive_registry_issue52_test.dart) fails for one that does not.
Widget _screen(GoRouterState state, Widget screen, {required bool roster}) =>
    isSensitiveLocation(state.matchedLocation, roster: roster)
        ? SecureScope(child: SensitiveGate(child: screen))
        : screen;

/// Auth-gated router. Redirect reads [TeamAuthBloc] state; the app calls
/// `router.refresh()` when that state changes: splash → login → five-tab shell.
///
/// [modules] answers which staff modules the signed-in person has. A module
/// route (one prefix per module, [TeamModule]) that is not among them falls
/// back to `/home` (team_app #50, item 7), and [onModuleBlocked] is told the
/// full location it refused. The app builds its router in `TeamRouterHost`
/// (team_router_host.dart), which reads [modules] from `TeamModulesBloc`
/// (item 7b), runs the guards again when the open modules change, and opens a
/// refused location once the first answer opens its module. The default here
/// is none.
///
/// [secureRoster] blocks screenshots of the class roster (team_app #52 item
/// 1). It is off unless the build turns it on ([secureRosterOn]).
GoRouter createRouter(TeamAuthBloc authBloc,
    {GlobalKey<NavigatorState>? navigatorKey,
    Set<TeamModule> Function() modules = noTeamModules,
    void Function(String location)? onModuleBlocked,
    bool secureRoster = secureRosterOn}) {
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
          if (authBloc.state.identity?.attendance == true &&
              attendanceBlockedLocation(loc)) {
            return '/home';
          }
          if (moduleBlockedLocation(loc, modules())) {
            onModuleBlocked?.call(state.uri.toString());
            return '/home';
          }
          return (loc == '/splash' || authOnly.contains(loc)) ? '/home' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/forgot', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/home', builder: (_, __) => const TeamShell()),
      // ── Stage 2/3 modules (#52–#58) ─────────────────────────────────────
      GoRoute(
          path: '/security/wait',
          builder: (_, state) =>
              _screen(state, const SecurityWaitScreen(), roster: secureRoster)),
      GoRoute(
          path: '/security/alerts',
          builder: (_, state) => _screen(
              state, const SecurityAlertsScreen(),
              roster: secureRoster)),
      GoRoute(
          path: '/security/phones',
          builder: (_, state) => _screen(
              state, const PhoneApprovalsScreen(),
              roster: secureRoster)),
      GoRoute(
          path: '/ops',
          builder: (_, state) =>
              _screen(state, const OpsHomeScreen(), roster: secureRoster)),
      GoRoute(
          path: '/ops/absent',
          builder: (_, state) => _screen(
              state, const AbsentStreaksScreen(),
              roster: secureRoster)),
      GoRoute(
          path: '/fees',
          builder: (_, state) =>
              _screen(state, const FeesListScreen(), roster: secureRoster)),
      GoRoute(
        path: '/fees/:id',
        builder: (_, state) => _screen(
          state,
          FeeDetailScreen(admissionId: state.pathParameters['id'] ?? ''),
          roster: secureRoster,
        ),
      ),
      GoRoute(
          path: '/scorecards',
          builder: (_, state) => _screen(
              state, const ScorecardScreen(),
              roster: secureRoster)),
      GoRoute(
          path: '/scorecards/branches',
          builder: (_, state) => _screen(
              state, const BranchScorecardsScreen(),
              roster: secureRoster)),
      GoRoute(
          path: '/scorecards/ceo',
          builder: (_, state) => _screen(
              state, const CeoScorecardScreen(),
              roster: secureRoster)),
      GoRoute(
          path: '/scorecards/targets',
          builder: (_, state) => _screen(
              state, const TargetsScreen(),
              roster: secureRoster)),
      GoRoute(
          path: '/tasks',
          builder: (_, state) =>
              _screen(state, const MyTasksScreen(), roster: secureRoster)),
      GoRoute(
          path: '/social',
          builder: (_, state) =>
              _screen(state, const SocialHomeScreen(), roster: secureRoster)),
      GoRoute(
          path: '/social/board',
          builder: (_, state) => _screen(
              state, const SocialBoardScreen(),
              roster: secureRoster)),
      GoRoute(
          path: '/social/calendar',
          builder: (_, state) => _screen(
              state, const SocialCalendarScreen(),
              roster: secureRoster)),
      GoRoute(
        path: '/social/card/:id',
        builder: (_, state) => _screen(
          state,
          SocialCardScreen(cardId: state.pathParameters['id'] ?? ''),
          roster: secureRoster,
        ),
      ),
      GoRoute(
          path: '/desk',
          builder: (_, state) =>
              _screen(state, const DeskHomeScreen(), roster: secureRoster)),
      GoRoute(
          path: '/desk/link',
          builder: (_, state) =>
              _screen(state, const LinkPhoneScreen(), roster: secureRoster)),
      GoRoute(
          path: '/desk/phone-changes',
          builder: (_, state) => _screen(
              state, const PhoneChangesScreen(),
              roster: secureRoster)),
      GoRoute(
          path: '/desk/views',
          builder: (_, state) =>
              _screen(state, const ViewRequestsScreen(),
              roster: secureRoster)),
      GoRoute(
          path: '/placement',
          builder: (_, state) => _screen(
              state, const PlacementHomeScreen(),
              roster: secureRoster)),
      GoRoute(
        path: '/placement/verify/:id',
        builder: (_, state) => _screen(
          state,
          PlacementVerifyScreen(id: state.pathParameters['id'] ?? ''),
          roster: secureRoster,
        ),
      ),
      GoRoute(
          path: '/complaints',
          builder: (_, state) => _screen(
              state, const ComplaintsScreen(),
              roster: secureRoster)),
      GoRoute(
        path: '/complaints/:id',
        builder: (_, state) => _screen(
          state,
          ComplaintThreadScreen(id: state.pathParameters['id'] ?? ''),
          roster: secureRoster,
        ),
      ),
      GoRoute(
          path: '/moderation',
          builder: (_, state) => _screen(
              state, const ModerationScreen(),
              roster: secureRoster)),
      // ── Sales CRM (team_app #51) ─────────────────────────────────────────
      GoRoute(
          path: '/crm',
          builder: (_, state) => _screen(state, const CrmHomeScreen(),
              roster: secureRoster)),
      GoRoute(
        path: '/crm/leads',
        builder: (_, state) => _screen(
          state,
          CrmLeadsScreen(
            initialBucket: _crmBucket(state.uri.queryParameters['bucket']),
          ),
          roster: secureRoster,
        ),
      ),
      GoRoute(
          path: '/crm/calendar',
          builder: (_, state) => _screen(
              state, const CrmCalendarScreen(),
              roster: secureRoster)),
      GoRoute(
          path: '/crm/add',
          builder: (_, state) =>
              _screen(state, const CrmAddLeadScreen(), roster: secureRoster)),
      GoRoute(
        path: '/crm/call/:callId',
        builder: (_, state) => _screen(
          state,
          CrmCallScreen(
            callId: _int(state.pathParameters['callId']) ?? 0,
            leadId: _int(state.uri.queryParameters['leadId']) ?? 0,
          ),
          roster: secureRoster,
        ),
      ),
      GoRoute(
        path: '/crm/lead/:id/dispose',
        builder: (_, state) => _screen(
          state,
          CrmDispositionScreen(
            leadId: _int(state.pathParameters['id']) ?? 0,
            callId: _int(state.uri.queryParameters['callId']) ?? 0,
            origin: state.uri.queryParameters['origin'] ?? 'dialer',
            autoDial: state.uri.queryParameters['autoDial'] == '1',
          ),
          roster: secureRoster,
        ),
      ),
      GoRoute(
        path: '/crm/lead/:id',
        builder: (_, state) => _screen(
          state,
          CrmLeadScreen(leadId: _int(state.pathParameters['id']) ?? 0),
          roster: secureRoster,
        ),
      ),
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
        path: '/work/batch/:id/marks',
        builder: (_, state) => _screen(
          state,
          MarksScreen(
            batchId: state.pathParameters['id']!,
            batchName: state.extra is String ? state.extra as String : null,
          ),
          roster: secureRoster,
        ),
      ),
      GoRoute(
        path: '/work/batch/:id/mark',
        builder: (_, state) => _screen(
          state,
          MarkAttendanceScreen(
            batchId: state.pathParameters['id']!,
            batchName: state.extra is String ? state.extra as String : null,
          ),
          roster: secureRoster,
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
      GoRoute(
          path: '/hr/wfh-allowances',
          builder: (_, __) => const HrWfhAllowancesScreen()),
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

import 'package:domain/domain.dart';

import '../domain/ess_models.dart';

/// What a role may see and do in Team RVM, limited to what the Scheduler
/// backend actually serves today. Encoded from `Scheduler_Backend`:
///
/// - Priority tasks read = `requireRole(admin)` → admin, super_admin,
///   admin_manager, hoo, ceo (admin's inheritors). NOT hr, faculty, hod.
/// - Faculty work (batches + student attendance) = `hasRole(faculty)`; a HOD
///   inherits faculty. The `GET /api/batches` reply is filtered server-side to
///   the caller's own batches for faculty.
/// - Interviews = open to any authenticated caller (the reply is empty unless
///   the caller is on a panel).
/// - Sales Executive = fenced to its own workspace (`SALES_WORKSPACE_PATHS` in
///   `middleware/auth.js`: `/api/sales-dialer`, `/api/me`,
///   `/api/users/change-password`, `/api/hr/my-attendance`). Everything else
///   answers 403 `SALES_WORKSPACE_ONLY`, so the priority-task Inbox, interviews
///   and branch announcements are hidden for it (team_app #50, item 4).
class TeamPermissions {
  const TeamPermissions({
    required this.role,
    required this.canSeePriorityTasks,
    required this.canSeeFacultyWork,
    required this.canSeeInterviews,
    required this.canSeeHodWork,
    required this.canWriteHod,
    required this.canSeeInbox,
    required this.canSeeAnnouncements,
  });

  final AppRole role;
  final bool canSeePriorityTasks;
  final bool canSeeFacultyWork;
  final bool canSeeInterviews;

  /// Faculty Development (`/api/hod/*`) — HOD, HoO, super admin, CEO.
  final bool canSeeHodWork;

  /// May fill Faculty Development sheets (risk logs, comments, verdicts) —
  /// FD_WRITE_ROLES = HOD, super admin, CEO. The HoO only oversees.
  final bool canWriteHod;

  /// The Inbox tab: priority tasks, or a teaching role's batch attendance.
  /// Both are Scheduler reads outside the sales workspace.
  final bool canSeeInbox;

  /// Branch announcements (Scheduler `GET /api/announcements`) on Home.
  final bool canSeeAnnouncements;

  static bool _adminLevel(AppRole r) => switch (r) {
        AppRole.admin ||
        AppRole.superAdmin ||
        AppRole.adminManager ||
        AppRole.hoo ||
        AppRole.ceo ||
        AppRole.accountsAdmin =>
          true,
        _ => false,
      };

  factory TeamPermissions.forRole(AppRole role) {
    final faculty = role == AppRole.faculty || role == AppRole.hod;
    final hod = role == AppRole.hod ||
        role == AppRole.hoo ||
        role == AppRole.superAdmin ||
        role == AppRole.ceo;
    final hodWrite = role == AppRole.hod || role == AppRole.superAdmin || role == AppRole.ceo;
    final salesOnly = role == AppRole.salesExecutive;
    return TeamPermissions(
      role: role,
      canSeePriorityTasks: _adminLevel(role),
      canSeeFacultyWork: faculty,
      canSeeInterviews: !salesOnly,
      canSeeHodWork: hod,
      canWriteHod: hodWrite,
      canSeeInbox: !salesOnly,
      canSeeAnnouncements: !salesOnly,
    );
  }
}

/// Who is looking: what every tab, Home card and Me tile rule reads
/// (team_app #50, item 6).
class TeamViewer {
  TeamViewer({required this.role, this.attendance = false, this.caps})
      : perms = TeamPermissions.forRole(role);

  final AppRole role;

  /// An attendance-only sign-in: a punch token with no portal role, which the
  /// Scheduler accepts only on the punch routes.
  final bool attendance;

  /// The ESS capabilities, once they have loaded.
  final EssCapabilities? caps;

  final TeamPermissions perms;
}

/// The badges this sign-in may give. The server holds the same list and refuses
/// a reserved badge from anybody else, so hiding it here is a courtesy, not the
/// permission itself (KP, issue 24 follow-up).
List<PraiseBadge> awardablePraiseBadges(
    List<PraiseBadge> badges, AppRole role) {
  final wire = appRoleWire(role);
  return badges
      .where((badge) =>
          badge.awardedBy.isEmpty ||
          (wire != null && badge.awardedBy.contains(wire)))
      .toList(growable: false);
}

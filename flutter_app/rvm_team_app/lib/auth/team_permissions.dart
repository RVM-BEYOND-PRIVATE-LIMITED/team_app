import 'package:domain/domain.dart';

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
class TeamPermissions {
  const TeamPermissions({
    required this.role,
    required this.canSeePriorityTasks,
    required this.canSeeFacultyWork,
    required this.canSeeInterviews,
    required this.canSeeHodWork,
    required this.canWriteHod,
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
    return TeamPermissions(
      role: role,
      canSeePriorityTasks: _adminLevel(role),
      canSeeFacultyWork: faculty,
      canSeeInterviews: true,
      canSeeHodWork: hod,
      canWriteHod: hodWrite,
    );
  }
}

import '../mappers/enum_parsers.dart';
import '../util/jwt.dart';
import 'auth_user.dart';

/// The signed-in staff member for the session — ONE role per session. Built from
/// the login `user` object and/or the decoded JWT claims (session restore).
class StaffIdentity {
  const StaffIdentity({
    required this.userId,
    required this.role,
    this.facultyId,
    this.locationId,
    this.locationName,
    this.username,
    this.attendance = false,
  });

  final String userId;
  final AppRole role;
  final String? facultyId;
  final int? locationId;
  final String? locationName;
  final String? username;

  /// True when the session is a Scheduler *attendance* session (an
  /// attendance-only login with no portal role). Team RVM admits these; the
  /// staff/student apps do not.
  final bool attendance;

  /// Admitted to Team RVM: a portal staff login or an attendance-only login.
  ///
  /// Wider than [isStaff] by the roles the ESS serves but staff_app refuses —
  /// HR, HR Executive and HOD (Placement). `team_app`'s
  /// `policy/capabilities.js` names them all (HR_SCOPE, WORK_ROLES), so these
  /// are valid Team RVM logins and must not be turned away.
  bool get isTeamMember =>
      isStaff ||
      role == AppRole.hr ||
      role == AppRole.hrExecutive ||
      role == AppRole.hodPlacement ||
      attendance;

  /// Location-scope bypass — backend SEES_ALL_LOCATIONS (ceo, super_admin,
  /// accounts_admin). Everyone else is branch-locked.
  bool get isSuperAdmin =>
      role == AppRole.ceo || role == AppRole.superAdmin || role == AppRole.accountsAdmin;

  /// Staff roles allowed in staff_app. Rejected: student, unknown, and hr /
  /// hod_placement (their backend workspaces — HR, interview calendar — exist
  /// only on the web portal; every staff-app endpoint refuses them).
  bool get isStaff => switch (role) {
        AppRole.admin ||
        AppRole.faculty ||
        AppRole.superAdmin ||
        AppRole.accountsAdmin ||
        AppRole.ceo ||
        AppRole.hoo ||
        AppRole.hod ||
        AppRole.adminManager ||
        AppRole.adminExecutive ||
        AppRole.placementHead ||
        AppRole.placementExecutive =>
          true,
        _ => false,
      };

  /// From the login response `user` object.
  factory StaffIdentity.fromLoginUser(Map<String, dynamic> user) => StaffIdentity(
        userId: (user['userId'] ?? user['id'] ?? '').toString(),
        role: parseAppRole(user['role']?.toString()),
        facultyId: user['faculty_id']?.toString(),
        locationId: _int(user['locationId']),
        locationName: user['locationName']?.toString(),
        username: user['username']?.toString(),
      );

  /// From decoded JWT claims (relaunch restore). Claim `id` == faculty_id for
  /// teaching roles (backend TEACHING_ROLES: faculty, hod).
  factory StaffIdentity.fromClaims(Map<String, dynamic> claims) {
    final role = parseAppRole(claims['role']?.toString());
    final teaching = role == AppRole.faculty || role == AppRole.hod;
    return StaffIdentity(
      userId: (claims['userId'] ?? claims['id'] ?? '').toString(),
      role: role,
      facultyId: teaching ? claims['id']?.toString() : null,
      locationId: _int(claims['locationId']),
      locationName: claims['locationName']?.toString(),
      username: claims['username']?.toString(),
    );
  }

  /// Restore from a stored JWT (returns null if the token has no usable claims).
  static StaffIdentity? fromToken(String? token) {
    final claims = Jwt.decodePayload(token);
    if (claims.isEmpty) return null;
    // A Scheduler attendance session carries `k: "punch"`, the employee id in
    // `e`, and no portal `role` (ADR-0006 / core_network EssAuthInterceptor).
    if (claims['k'] == 'punch') {
      return StaffIdentity(
        userId: (claims['e'] ?? '').toString(),
        role: AppRole.unknown,
        attendance: true,
      );
    }
    if (claims['role'] == null) return null;
    return StaffIdentity.fromClaims(claims);
  }

  static int? _int(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
}

/// A Scheduler user account as the super-admin provisioning console sees it
/// (GET /users → `[{id, username, phone_number, role, location_id, created_at}]`).
class StaffUser {
  const StaffUser({
    required this.id,
    required this.username,
    this.phoneNumber,
    this.role,
    this.locationId,
    this.createdAt,
  });

  final String id;
  final String username;
  final String? phoneNumber;

  /// Raw wire role (e.g. 'admin', 'super_admin', 'accounts_admin', 'faculty').
  final String? role;
  final int? locationId;
  final DateTime? createdAt;
}

/// POST /users/super-provision body — create a user at any branch/role. The
/// backend requires a [locationId] for every role except accounts_admin (global).
class UserProvisionDraft {
  const UserProvisionDraft({
    required this.username,
    required this.password,
    required this.role,
    this.phoneNumber,
    this.locationId,
    this.facultyId,
  });

  final String username;
  final String password;
  final String role;
  final String? phoneNumber;
  final int? locationId;
  final String? facultyId;

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        'role': role,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (locationId != null) 'location_id': locationId,
        if (facultyId != null) 'faculty_id': facultyId,
      };
}

/// PATCH /users/update/:id body — only the provided fields change; a non-empty
/// [password] resets it.
class UserUpdate {
  const UserUpdate({this.username, this.phoneNumber, this.role, this.password, this.locationId});

  final String? username;
  final String? phoneNumber;
  final String? role;
  final String? password;
  final int? locationId;

  Map<String, dynamic> toJson() => {
        if (username != null) 'username': username,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (role != null) 'role': role,
        if (password != null && password!.isNotEmpty) 'password': password,
        if (locationId != null) 'location_id': locationId,
      };
}

/// POST /users/reset-password body — public forgot-password (verified by
/// username + phone match; [locationName] narrows a multi-branch match).
class ResetPasswordDraft {
  const ResetPasswordDraft({
    required this.username,
    required this.phoneNumber,
    required this.newPassword,
    this.locationName,
  });

  final String username;
  final String phoneNumber;
  final String newPassword;
  final String? locationName;

  Map<String, dynamic> toJson() => {
        'username': username,
        'phone_number': phoneNumber,
        'new_password': newPassword,
        if (locationName != null) 'locationName': locationName,
      };
}

/// The roles a super-admin can provision / assign (wire values).
const kProvisionableRoles = <String>[
  'admin',
  'accounts_admin',
  'faculty',
  'admin_executive',
  'placement_head',
  'placement_executive',
  'super_admin',
];

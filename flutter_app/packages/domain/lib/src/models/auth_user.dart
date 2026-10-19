/// Who is signed in, normalised across both backends' role vocabularies.
enum AppRole {
  // Scheduler (staff) roles — mirror Scheduler_Backend/config/roles.js.
  admin,
  faculty,
  superAdmin,
  accountsAdmin,
  ceo,
  hoo,
  hod,
  adminManager,
  hr,
  hrExecutive,
  hodPlacement,
  // Legacy role strings (no longer in config/roles.js); kept so old tokens parse.
  adminExecutive,
  placementHead,
  placementExecutive,
  student,
  // JobPortal roles
  candidate,
  company,
  unknown,
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.role,
    this.name,
    this.locationId,
    this.locationName,
  });

  final String id;
  final AppRole role;
  final String? name;
  final int? locationId;
  final String? locationName;
}

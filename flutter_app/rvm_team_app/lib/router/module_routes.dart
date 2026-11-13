/// The staff modules the Team app is being readied for, one route prefix each
/// (team_app #50, "Route prefixes"). Test marks sit under the existing `/work`
/// prefix, and the modules attendance-only staff use (`/tasks`, `/social`) stay
/// out of `/work` and `/hr`, which `attendanceBlockedLocation` (app_router.dart)
/// closes to them.
///
/// Which modules a person has will come from the Scheduler's modules reply
/// (Scheduler_Backend#157 / #175; team_app #50 items 5 and 7b). Until that
/// exists nobody has a module, so every module route falls back to `/home`.
enum TeamModule {
  crm('/crm', sensitive: true),
  fees('/fees', sensitive: true),
  ops('/ops'),
  desk('/desk', sensitive: true),
  placement('/placement', sensitive: true),
  scorecards('/scorecards'),
  tasks('/tasks'),
  social('/social'),
  complaints('/complaints', sensitive: true),
  moderation('/moderation');

  const TeamModule(this.routePrefix, {this.sensitive = false});

  /// The module's own route prefix; its screens live at or under it.
  final String routePrefix;

  /// The module shows student or lead data: its screens block screenshots
  /// (team_app #52, item 1). Marked here once, for the modules the issue names
  /// (CRM, fees follow-up, student desk, placement checks, complaints).
  final bool sensitive;
}

/// No modules: what everybody has until the modules reply exists.
Set<TeamModule> noTeamModules() => const {};

/// The module whose prefix [location] sits at or under, or null for every
/// other route (`/home`, `/work/…`, `/hr/…`, `/me/…`, `/wall/moderation`, …).
TeamModule? moduleForLocation(String location) {
  for (final module in TeamModule.values) {
    final prefix = module.routePrefix;
    if (location == prefix || location.startsWith('$prefix/')) return module;
  }
  return null;
}

/// True when [location] is a module route that is not in [granted]. The router
/// sends such a location to `/home`, the same way a stale or deep link to a
/// screen the person cannot use is handled for attendance-only sign-ins.
bool moduleBlockedLocation(String location, Set<TeamModule> granted) {
  final module = moduleForLocation(location);
  return module != null && !granted.contains(module);
}

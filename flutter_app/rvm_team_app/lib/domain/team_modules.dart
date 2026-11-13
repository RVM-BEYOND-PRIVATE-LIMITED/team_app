import 'package:equatable/equatable.dart';

import '../router/module_routes.dart';

/// The staff modules open to the signed-in person, each with its `dry_run`
/// flag (team_app #50, item 5), from the Scheduler's
/// `GET /api/me/features` → `{ features: [{ key, dry_run }] }`
/// (Scheduler_Backend routes/meFeatures.js). The reply lists only the switches
/// open to the caller: `on`, or `pilot` with the caller's user id or branch.
///
/// The reply has no level field. Any decision by level uses the role already
/// in the session (`StaffIdentity.role`).
class TeamModules extends Equatable {
  const TeamModules._(this._dryRun);

  /// Each open module and whether it runs dry ([isDryRun]).
  TeamModules(Map<TeamModule, bool> dryRun)
      : _dryRun = Map.unmodifiable(dryRun);

  /// Nothing open: before the reply, when it fails, and when it opens nothing.
  /// The app then looks exactly as it does without modules.
  static const none = TeamModules._({});

  /// The modules in a reply [body]. Never throws: a body that is not the
  /// documented shape opens nothing, an entry that is not one is skipped, and
  /// a key the app does not know ([teamModuleForKey]) is ignored.
  factory TeamModules.fromJson(Object? body) {
    if (body is! Map) return none;
    final features = body['features'];
    if (features is! List) return none;
    final open = <TeamModule, bool>{};
    for (final entry in features) {
      if (entry is! Map) continue;
      final module = teamModuleForKey(entry['key']);
      if (module == null) continue;
      // The server sends `row.dry_run === true`; anything else is not dry.
      open[module] = entry['dry_run'] == true;
    }
    return open.isEmpty ? none : TeamModules(open);
  }

  final Map<TeamModule, bool> _dryRun;

  /// The open modules: what the router's module guard lets through.
  Set<TeamModule> get open => _dryRun.keys.toSet();

  bool get isEmpty => _dryRun.isEmpty;

  bool has(TeamModule module) => _dryRun.containsKey(module);

  /// True when [module] is open and its switch has `dry_run` set. What a
  /// module does in a dry run is the module's own rule; false for a module
  /// that is not open.
  bool isDryRun(TeamModule module) => _dryRun[module] ?? false;

  @override
  List<Object?> get props => [_dryRun];

  @override
  String toString() =>
      'TeamModules(${{for (final e in _dryRun.entries) e.key.key: e.value}})';
}

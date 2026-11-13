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
///
/// The reply is worked out from the caller's user id and branch only
/// (`defaultWho`). A switch whose pilot names the person only by HR employee
/// or by subject (`pilot_employee_ids`, `pilot_subject_ids`) is never listed,
/// even where the module's own guard would admit them, so the app keeps that
/// module closed. See docs/team-modules.md, "Gaps".
class TeamModules extends Equatable {
  const TeamModules._(this._dryRun);

  /// Each open module and whether it runs dry ([isDryRun]).
  TeamModules(Map<TeamModule, bool> dryRun)
      : _dryRun = Map.unmodifiable(dryRun);

  /// Nothing open: before the first answer of a sign-in, when that first ask
  /// fails, and when the answer opens nothing. The app then looks exactly as
  /// it does without modules.
  static const none = TeamModules._({});

  /// The modules in a reply [body]. Never throws: a body that is not the
  /// documented shape opens nothing ([tryParse] tells that case apart).
  factory TeamModules.fromJson(Object? body) => tryParse(body) ?? none;

  /// The modules in a reply [body], or null when [body] is not the documented
  /// `{ features: [...] }` at all (a proxy's HTML page, say): that is no
  /// answer, which is not the same as an answer that opens nothing. Never
  /// throws: an entry that is not `{ key, dry_run }` is skipped, and a key the
  /// app does not know ([teamModuleForKey]) is ignored.
  static TeamModules? tryParse(Object? body) {
    if (body is! Map) return null;
    final features = body['features'];
    if (features is! List) return null;
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

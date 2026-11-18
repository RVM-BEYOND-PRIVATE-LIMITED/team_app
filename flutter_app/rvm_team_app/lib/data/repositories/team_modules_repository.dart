import 'package:core_network/core_network.dart';

import '../../domain/team_modules.dart';
import '../connectivity_guard.dart';
import '../datasources/team_modules_remote_data_source.dart';

/// Which staff modules the signed-in person has (team_app #50, item 5).
class TeamModulesRepository with ConnectivityGuard {
  TeamModulesRepository({
    required TeamModulesRemoteDataSource remote,
    required this.connectivity,
  }) : _remote = remote;

  final TeamModulesRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  /// The code the Scheduler's own 404s carry: production's `/api` catch-all
  /// (`API endpoint not found.`) and a closed switch's `Not found`.
  static const _schedulerNotFound = 'NOT_FOUND';

  /// The open modules, or null when the server gave no answer about them.
  /// Never throws, like the shell's capabilities check.
  ///
  /// An answer:
  ///  * 200: what it lists, which may be nothing.
  ///  * 403 (a student token, `Access denied. Staff only.`): nothing open.
  ///  * The Scheduler's 404 `NOT_FOUND` (a server without the route, such as
  ///    production today): nothing open.
  ///
  /// No answer (null): offline (nothing is sent), a timeout, a connection that
  /// never opens, a 401 (this request never ends the session, so it says
  /// nothing about the modules), a 5xx such as 500
  /// `Could not load your features.`, a 404 without the Scheduler's code (a
  /// proxy's page), or a reply that cannot be read. `TeamModulesBloc` then
  /// keeps what is open: nothing before the first answer of a sign-in.
  Future<TeamModules?> modules() async {
    try {
      await ensureOnline();
      return await _remote.features();
    } on ForbiddenFailure {
      return TeamModules.none;
    } on NotFoundFailure catch (failure) {
      return failure.code == _schedulerNotFound ? TeamModules.none : null;
    } catch (_) {
      return null;
    }
  }
}

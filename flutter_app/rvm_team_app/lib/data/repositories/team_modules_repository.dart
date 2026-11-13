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

  /// The open modules, without throwing, like the shell's capabilities check.
  /// Every failure is [TeamModules.none]: offline (no request is sent), a
  /// timeout, 401, 403 (a student token), 404 (a server that does not have
  /// the route yet, which production answers `NOT_FOUND`), 5xx, or a reply
  /// that cannot be read. The app then looks as it does without modules.
  Future<TeamModules> modules() async {
    try {
      await ensureOnline();
      return await _remote.features();
    } catch (_) {
      return TeamModules.none;
    }
  }
}

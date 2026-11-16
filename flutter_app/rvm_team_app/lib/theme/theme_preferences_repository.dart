import 'package:core_network/core_network.dart';

import '../data/connectivity_guard.dart';
import 'theme_preference.dart';
import 'theme_preferences_remote_data_source.dart';

/// Reads and saves the person's appearance choice on the Scheduler.
class ThemePreferencesRepository with ConnectivityGuard {
  ThemePreferencesRepository({
    required ThemePreferencesRemoteDataSource remote,
    required this.connectivity,
  }) : _remote = remote;

  final ThemePreferencesRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<ThemePreference> load() async {
    await ensureOnline();
    return _remote.getPreference();
  }

  Future<ThemePreference> save(
    ThemeChoice choice, {
    String? idempotencyKey,
  }) async {
    await ensureOnline();
    return _remote.savePreference(choice, idempotencyKey: idempotencyKey);
  }
}

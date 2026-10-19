import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/activities_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff recent-activity feed (Scheduler). Connectivity-guarded pass-through.
class ActivitiesRepository with ConnectivityGuard {
  ActivitiesRepository({required ActivitiesRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final ActivitiesRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<Activity>> list({String? locationId}) async {
    await ensureOnline();
    return _remote.list(locationId: locationId);
  }
}

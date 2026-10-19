import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/alerts_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff pending-alerts (Scheduler). Connectivity-guarded pass-throughs over the
/// data source — the branch's unresolved alerts plus single + bulk resolve.
class AlertsRepository with ConnectivityGuard {
  AlertsRepository({required AlertsRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final AlertsRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<PendingAlert>> pending({String? locationId, String? alertType}) async {
    await ensureOnline();
    return _remote.pending(locationId: locationId, alertType: alertType);
  }

  Future<void> resolve(String id) async {
    await ensureOnline();
    return _remote.resolve(id);
  }

  Future<void> bulkResolve({required String date, String? alertType}) async {
    await ensureOnline();
    return _remote.bulkResolve(date: date, alertType: alertType);
  }
}

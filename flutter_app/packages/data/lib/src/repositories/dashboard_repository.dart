import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/dashboard_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff dashboard (Scheduler). Combines the KPI metrics with the yesterday-
/// attendance card into one [DashboardSummary].
class DashboardRepository with ConnectivityGuard {
  DashboardRepository({required DashboardRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final DashboardRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<DashboardSummary> summary() async {
    await ensureOnline();
    // Fetch both cards in parallel; attendance is a non-critical stub so its
    // failure shouldn't sink the whole dashboard.
    final metrics = await _remote.metrics();
    int attendance = 0;
    try {
      attendance = await _remote.yesterdayAttendance();
    } on Failure {
      attendance = 0;
    }
    return DashboardSummary(metrics: metrics, yesterdayAttendance: attendance);
  }
}

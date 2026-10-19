import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/followups_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff follow-up task management (Scheduler). Connectivity-guarded
/// pass-throughs — the task worklist, staff report, per-admission history, and
/// the create-log write.
class FollowUpsRepository with ConnectivityGuard {
  FollowUpsRepository({required FollowUpsRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final FollowUpsRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<FollowUpTasksPage> tasks({String? dateFilter, String? searchTerm, String? locationId}) async {
    await ensureOnline();
    return _remote.tasks(dateFilter: dateFilter, searchTerm: searchTerm, locationId: locationId);
  }

  Future<StaffFollowUpReport> staffReport({
    required DateTime start,
    required DateTime end,
    String? locationId,
  }) async {
    await ensureOnline();
    return _remote.staffReport(start: start, end: end, locationId: locationId);
  }

  Future<List<FollowUpLog>> history(String admissionId) async {
    await ensureOnline();
    return _remote.history(admissionId);
  }

  Future<void> createLog(FollowUpLogDraft draft) async {
    await ensureOnline();
    return _remote.createLog(draft);
  }
}

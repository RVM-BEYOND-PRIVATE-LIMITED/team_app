import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/batches_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff batch console (Scheduler). Connectivity-guarded pass-throughs plus the
/// combined [overview] load (list + active-students KPI) for the landing.
class BatchesRepository with ConnectivityGuard {
  BatchesRepository({required BatchesRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final BatchesRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  /// Landing: the batch list + the header KPI. The KPI is non-critical — its
  /// failure degrades to null rather than sinking the list.
  Future<BatchesOverview> overview({
    String? facultyId,
    String? locationId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await ensureOnline();
    final batches = await _remote.list(
      facultyId: facultyId,
      locationId: locationId,
      startDate: startDate,
      endDate: endDate,
    );
    ActiveStudentsCount? count;
    try {
      count = await _remote.activeStudentsCount(locationId: locationId);
    } on Failure {
      count = null;
    }
    return BatchesOverview(batches: batches, activeCount: count);
  }

  Future<List<BatchStudent>> students(String batchId) async {
    await ensureOnline();
    return _remote.students(batchId);
  }

  Future<StaffBatch> create(BatchDraft draft) async {
    await ensureOnline();
    return _remote.create(draft);
  }

  Future<StaffBatch> update(String batchId, BatchDraft draft) async {
    await ensureOnline();
    return _remote.update(batchId, draft);
  }

  Future<void> delete(String batchId) async {
    await ensureOnline();
    return _remote.delete(batchId);
  }
}

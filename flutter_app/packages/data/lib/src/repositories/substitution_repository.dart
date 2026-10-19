import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/substitution_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff faculty substitution (Scheduler). Connectivity-guarded pass-throughs —
/// the active list plus the create/update/cancel + assign/merge operations.
class SubstitutionRepository with ConnectivityGuard {
  SubstitutionRepository({required SubstitutionRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final SubstitutionRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<Substitution>> list({String? locationId}) async {
    await ensureOnline();
    return _remote.list(locationId: locationId);
  }

  Future<void> create(SubstitutionDraft draft) async {
    await ensureOnline();
    return _remote.create(draft);
  }

  Future<void> update(String id, SubstitutionUpdate update) async {
    await ensureOnline();
    return _remote.update(id, update);
  }

  Future<void> cancel(String id) async {
    await ensureOnline();
    return _remote.cancel(id);
  }

  Future<void> assign({required String batchId, required String facultyId}) async {
    await ensureOnline();
    return _remote.assign(batchId: batchId, facultyId: facultyId);
  }

  Future<void> merge({required String sourceBatchId, required String targetBatchId}) async {
    await ensureOnline();
    return _remote.merge(sourceBatchId: sourceBatchId, targetBatchId: targetBatchId);
  }
}

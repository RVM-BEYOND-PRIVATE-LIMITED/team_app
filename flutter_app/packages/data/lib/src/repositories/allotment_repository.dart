import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/allotment_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff batch-allotment (Scheduler). Connectivity-guarded pass-throughs — the
/// worklist, per-student follow-up + remark history, the allotment update +
/// follow-up writes, and the red-flag (at-risk) views.
class AllotmentRepository with ConnectivityGuard {
  AllotmentRepository({required AllotmentRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final AllotmentRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<AllotmentRow>> list({String? search, String? locationId}) async {
    await ensureOnline();
    return _remote.list(search: search, locationId: locationId);
  }

  Future<void> update(String admissionId, AllotmentUpdate update) async {
    await ensureOnline();
    return _remote.update(admissionId, update);
  }

  Future<List<AdmissionRemark>> remarkHistory(String admissionId) async {
    await ensureOnline();
    return _remote.remarkHistory(admissionId);
  }

  Future<FollowUpHistory> followUps(String admissionId) async {
    await ensureOnline();
    return _remote.followUps(admissionId);
  }

  Future<FollowUp> createFollowUp(String admissionId, FollowUpDraft draft) async {
    await ensureOnline();
    return _remote.createFollowUp(admissionId, draft);
  }

  Future<List<RedFlagStudent>> redStudents({String? search, String? locationId}) async {
    await ensureOnline();
    return _remote.redStudents(search: search, locationId: locationId);
  }

  Future<RedFlagSummary> redFlagSummary({String? locationId}) async {
    await ensureOnline();
    return _remote.redFlagSummary(locationId: locationId);
  }
}

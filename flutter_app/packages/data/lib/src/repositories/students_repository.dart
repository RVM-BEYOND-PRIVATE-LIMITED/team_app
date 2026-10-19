import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/students_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff student master (Scheduler). Connectivity-guarded pass-throughs over the
/// data source — the list, per-student batches/defaulter reads, and the CRUD +
/// transfer + defaulter + hold writes.
class StudentsRepository with ConnectivityGuard {
  StudentsRepository({required StudentsRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final StudentsRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<StudentsPage> list({
    String? search,
    String? locationId,
    int page = 1,
    int limit = 20,
    bool onHold = false,
    bool feePending = false,
  }) async {
    await ensureOnline();
    return _remote.list(
      search: search,
      locationId: locationId,
      page: page,
      limit: limit,
      onHold: onHold,
      feePending: feePending,
    );
  }

  Future<List<StaffBatch>> batches(String studentId) async {
    await ensureOnline();
    return _remote.batches(studentId);
  }

  Future<DefaulterStatus> defaulterStatus(String studentId) async {
    await ensureOnline();
    return _remote.defaulterStatus(studentId);
  }

  Future<StaffStudent> create(StudentDraft draft) async {
    await ensureOnline();
    return _remote.create(draft);
  }

  Future<StaffStudent> update(String id, StudentDraft draft) async {
    await ensureOnline();
    return _remote.update(id, draft);
  }

  Future<void> delete(String id) async {
    await ensureOnline();
    return _remote.delete(id);
  }

  Future<void> transfer({required String id, required int newLocationId}) async {
    await ensureOnline();
    return _remote.transfer(id: id, newLocationId: newLocationId);
  }

  Future<void> markDefaulter({required String id, String? reason}) async {
    await ensureOnline();
    return _remote.markDefaulter(id: id, reason: reason);
  }

  Future<void> removeDefaulter(String id) async {
    await ensureOnline();
    return _remote.removeDefaulter(id);
  }

  Future<void> hold({required String id, required String category, required String remarks}) async {
    await ensureOnline();
    return _remote.hold(id: id, category: category, remarks: remarks);
  }

  Future<void> unhold(String id) async {
    await ensureOnline();
    return _remote.unhold(id);
  }
}

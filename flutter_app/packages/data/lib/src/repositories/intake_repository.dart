import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/intake_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff admission-intake worklist (Scheduler). Connectivity-guarded
/// pass-throughs over the data source — list + prefill read + finalize + the
/// (deferred-form) create.
class IntakeRepository with ConnectivityGuard {
  IntakeRepository({required IntakeRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final IntakeRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<Intake>> list() async {
    await ensureOnline();
    return _remote.list();
  }

  /// The candidate's own intake status by phone (app admission gate).
  Future<AdmissionIntakeStatus> statusByPhone(String phone) async {
    await ensureOnline();
    return _remote.statusByPhone(phone);
  }

  Future<IntakePrefill> proceed(String id) async {
    await ensureOnline();
    return _remote.proceed(id);
  }

  Future<void> finalize(String id) async {
    await ensureOnline();
    return _remote.finalize(id);
  }

  Future<(String, bool)> create(IntakeDraft draft) async {
    await ensureOnline();
    return _remote.create(draft);
  }

  Future<void> uploadFiles(String id, List<UploadFile> files) async {
    await ensureOnline();
    return _remote.uploadFiles(id, files);
  }
}

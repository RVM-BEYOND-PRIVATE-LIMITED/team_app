import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/admissions_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff admissions (Scheduler). Connectivity-guarded pass-throughs — the list
/// (+ metrics), detail, phone lookup, dropout registry, and the dropout /
/// reactivate / toggle-undertaking writes.
class AdmissionsRepository with ConnectivityGuard {
  AdmissionsRepository({required AdmissionsRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final AdmissionsRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<AdmissionsPage> list({String? search, String? locationId}) async {
    await ensureOnline();
    return _remote.list(search: search, locationId: locationId);
  }

  Future<AdmissionDetail> byId(String id) async {
    await ensureOnline();
    return _remote.byId(id);
  }

  Future<AdmissionPhoneCheck> byPhone(String phone) async {
    await ensureOnline();
    return _remote.byPhone(phone);
  }

  Future<List<AdmissionRow>> dropoutRegistry({String? search, String? locationId, String? from, String? to}) async {
    await ensureOnline();
    return _remote.dropoutRegistry(search: search, locationId: locationId, from: from, to: to);
  }

  Future<void> markDropout({required String id, String? reason}) async {
    await ensureOnline();
    return _remote.markDropout(id: id, reason: reason);
  }

  Future<void> reactivate(String id) async {
    await ensureOnline();
    return _remote.reactivate(id);
  }

  Future<void> toggleUndertaking({required String id, required bool completed}) async {
    await ensureOnline();
    return _remote.toggleUndertaking(id: id, completed: completed);
  }
}

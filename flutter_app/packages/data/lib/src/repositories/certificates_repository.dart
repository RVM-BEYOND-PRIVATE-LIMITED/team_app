import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/certificates_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff certificate catalog (Scheduler). Connectivity-guarded pass-throughs
/// over the data source — list + per-id read + the create/update/delete writes.
class CertificatesRepository with ConnectivityGuard {
  CertificatesRepository({required CertificatesRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final CertificatesRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<Certificate>> list() async {
    await ensureOnline();
    return _remote.list();
  }

  Future<Certificate> byId(String id) async {
    await ensureOnline();
    return _remote.byId(id);
  }

  Future<Certificate> create(CertificateDraft draft) async {
    await ensureOnline();
    return _remote.create(draft);
  }

  Future<Certificate> update(String id, CertificateDraft draft) async {
    await ensureOnline();
    return _remote.update(id, draft);
  }

  Future<void> delete(String id) async {
    await ensureOnline();
    return _remote.delete(id);
  }
}

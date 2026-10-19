import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/ceo_remote_data_source.dart';
import 'connectivity_guard.dart';

/// CEO command centre (Scheduler, super-admin). Connectivity-guarded
/// pass-throughs over the four dashboard endpoints.
class CeoRepository with ConnectivityGuard {
  CeoRepository({required CeoRemoteDataSource remote, required this.connectivity}) : _remote = remote;

  final CeoRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<CeoDashboard> dashboard({String? from, String? to, String? location}) async {
    await ensureOnline();
    return _remote.dashboard(from: from, to: to, location: location);
  }

  Future<List<CeoTrendPoint>> trends({required String from, required String to, String? location}) async {
    await ensureOnline();
    return _remote.trends(from: from, to: to, location: location);
  }

  Future<CeoCollectionIntel> collectionRate({String? location, String? method}) async {
    await ensureOnline();
    return _remote.collectionRate(location: location, method: method);
  }

  Future<CeoFacultyAttendance> facultyAttendance({String? location}) async {
    await ensureOnline();
    return _remote.facultyAttendance(location: location);
  }
}

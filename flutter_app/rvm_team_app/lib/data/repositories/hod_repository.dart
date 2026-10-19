import 'package:core_network/core_network.dart';

import '../connectivity_guard.dart';
import '../datasources/hod_remote_data_source.dart';
import '../../domain/models.dart';

/// HOD / Faculty Development reads and writes.
class HodRepository with ConnectivityGuard {
  HodRepository({required HodRemoteDataSource remote, required this.connectivity}) : _remote = remote;

  final HodRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<HodOverview> overview({String? month}) async {
    await ensureOnline();
    return _remote.overview(month: month);
  }

  Future<List<HodInterview>> interviews() async {
    await ensureOnline();
    return _remote.interviews();
  }

  Future<void> setVerdict(String id, {required String verdict, required String feedback}) async {
    await ensureOnline();
    return _remote.setVerdict(id, verdict: verdict, feedback: feedback);
  }

  Future<List<FacultyOption>> facultyOptions() async {
    await ensureOnline();
    return _remote.facultyOptions();
  }

  Future<void> createRiskLog({
    required String facultyId,
    String? facultyName,
    String? logDate,
    String entryType = 'one_on_one',
    String riskLevel = 'none',
    String? signal,
    String? actionTaken,
    bool escalated = false,
  }) async {
    await ensureOnline();
    return _remote.createRiskLog(
      facultyId: facultyId,
      facultyName: facultyName,
      logDate: logDate,
      entryType: entryType,
      riskLevel: riskLevel,
      signal: signal,
      actionTaken: actionTaken,
      escalated: escalated,
    );
  }

  Future<void> createFacultyComment({required String facultyId, required String comment}) async {
    await ensureOnline();
    return _remote.createFacultyComment(facultyId: facultyId, comment: comment);
  }
}

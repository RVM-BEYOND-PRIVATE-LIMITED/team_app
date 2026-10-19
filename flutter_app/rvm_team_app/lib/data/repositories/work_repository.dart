import 'package:core_network/core_network.dart';

import '../connectivity_guard.dart';
import '../datasources/work_remote_data_source.dart';
import '../../domain/models.dart';

/// Role work: batches, student attendance marking, interviews.
class WorkRepository with ConnectivityGuard {
  WorkRepository({required WorkRemoteDataSource remote, required this.connectivity}) : _remote = remote;

  final WorkRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<TeamBatch>> batches() async {
    await ensureOnline();
    return _remote.batches();
  }

  Future<List<AttendanceStudent>> dailyAttendance(String batchId, String date) async {
    await ensureOnline();
    return _remote.dailyAttendance(batchId, date);
  }

  Future<void> markAttendance({
    required String batchId,
    required String date,
    required Map<String, bool> present,
  }) async {
    await ensureOnline();
    return _remote.markAttendance(batchId: batchId, date: date, present: present);
  }

  Future<List<InterviewRound>> upcomingInterviews() async {
    await ensureOnline();
    return _remote.upcomingInterviews();
  }

  Future<List<InterviewRound>> interviews() async {
    await ensureOnline();
    return _remote.interviews();
  }

  Future<void> recordOutcome(String roundId, {required String outcome, required String remarks}) async {
    await ensureOnline();
    return _remote.recordOutcome(roundId, outcome: outcome, remarks: remarks);
  }

  Future<void> postponeInterview(String roundId, {required DateTime proposedAt, required String reason}) async {
    await ensureOnline();
    return _remote.postponeInterview(roundId, proposedAt: proposedAt, reason: reason);
  }

  Future<void> updateAbsentRemarks({
    required String attendanceId,
    String? absentReason,
    String? followUpComment,
  }) async {
    await ensureOnline();
    return _remote.updateAbsentRemarks(
      attendanceId: attendanceId,
      absentReason: absentReason,
      followUpComment: followUpComment,
    );
  }

  Future<FacultyReport> facultyReport(String facultyId, {required String startDate, required String endDate}) async {
    await ensureOnline();
    return _remote.facultyReport(facultyId, startDate: startDate, endDate: endDate);
  }
}

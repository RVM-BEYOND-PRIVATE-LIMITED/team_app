import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/attendance_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff attendance (Scheduler). Thin connectivity-guarded pass-through over the
/// data source, plus two combined loads the screens use: the [today] landing
/// (KPI + pending queue) and the [markSheet] (roster + history + pending).
class AttendanceRepository with ConnectivityGuard {
  AttendanceRepository({required AttendanceRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final AttendanceRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  // ── Combined loads ──────────────────────────────────────────────────────
  /// Landing snapshot for [date]: the pending-remarks queue grouped by batch +
  /// the lightweight today-summary KPI. The KPI is non-critical, so its failure
  /// degrades to null rather than sinking the whole screen.
  Future<AttendanceToday> today({required DateTime date, String? locationId}) async {
    await ensureOnline();
    final groups = await _remote.pendingRemarksByBatch(date: date);
    double? pct;
    try {
      pct = await _remote.todaySummary(locationId: locationId);
    } on Failure {
      pct = null;
    }
    return AttendanceToday(groups: groups, overallPercentage: pct);
  }

  /// Everything the mark screen needs for a batch+date in one shot. The last-N
  /// history dots + pending-remarks panel are non-critical enrichments, so
  /// their failure leaves the roster usable.
  Future<MarkSheet> markSheet({required String batchId, required DateTime date}) async {
    await ensureOnline();
    final entries = await _remote.daily(batchId: batchId, date: date);
    Map<String, List<AttendanceHistoryEntry>> history = const {};
    List<PendingRemark> pending = const [];
    try {
      history = await _remote.batchHistory(batchId);
    } on Failure {
      history = const {};
    }
    try {
      pending = await _remote.batchPendingRemarks(batchId);
    } on Failure {
      pending = const [];
    }
    return MarkSheet(entries: entries, historyByStudent: history, pendingRemarks: pending);
  }

  Future<void> save({
    required String batchId,
    required DateTime date,
    required List<AttendanceMark> marks,
  }) async {
    await ensureOnline();
    return _remote.save(batchId: batchId, date: date, marks: marks);
  }

  // ── Single-endpoint pass-throughs ───────────────────────────────────────
  Future<List<AttendanceEntry>> roster({required String batchId, required DateTime date}) async {
    await ensureOnline();
    return _remote.daily(batchId: batchId, date: date);
  }

  Future<List<AttendanceHistoryEntry>> studentHistory({
    required String batchId,
    required String studentId,
  }) async {
    await ensureOnline();
    return _remote.studentHistory(batchId: batchId, studentId: studentId);
  }

  Future<OverallAttendanceReport> overall({
    required DateTime start,
    required DateTime end,
    String? locationId,
  }) async {
    await ensureOnline();
    return _remote.overall(start: start, end: end, locationId: locationId);
  }

  Future<ComplianceReport> compliance({
    required DateTime start,
    required DateTime end,
    String? locationId,
  }) async {
    await ensureOnline();
    return _remote.compliance(start: start, end: end, locationId: locationId);
  }

  Future<FacultyAttendanceReport> facultyReport({
    required String facultyId,
    required DateTime start,
    required DateTime end,
    String? locationId,
  }) async {
    await ensureOnline();
    return _remote.facultyReport(facultyId: facultyId, start: start, end: end, locationId: locationId);
  }

  Future<BatchAttendanceReport> batchReport({
    required String batchId,
    required DateTime start,
    required DateTime end,
  }) async {
    await ensureOnline();
    return _remote.batchReport(batchId: batchId, start: start, end: end);
  }

  Future<void> updateRemark({
    required String attendanceId,
    String? absentReason,
    String? followUpComment,
  }) async {
    await ensureOnline();
    return _remote.updateRemark(
      attendanceId: attendanceId,
      absentReason: absentReason,
      followUpComment: followUpComment,
    );
  }
}

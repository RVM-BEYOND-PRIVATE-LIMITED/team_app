import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// One entry to save on the mark screen — student + present flag.
typedef AttendanceMark = ({String studentId, bool isPresent});

/// Scheduler attendance over the Bearer-JWT Dio. Backend auto-scopes reports to
/// the caller's branch (super-admin may pass [locationId] or omit for all).
/// Dates go over the wire as `YYYY-MM-DD` — the format both the daily fetch and
/// the report range filters expect.
class AttendanceRemoteDataSource with DioExecutor {
  AttendanceRemoteDataSource(this._dio);

  final Dio _dio;

  // ── Data management ─────────────────────────────────────────────────────
  /// POST /attendance — upsert the roster for a batch+date.
  Future<void> save({
    required String batchId,
    required DateTime date,
    required List<AttendanceMark> marks,
  }) =>
      guard(() async {
        await _dio.post('/attendance', data: {
          'batchId': batchId,
          'date': _ymd(date),
          'attendance': [
            for (final m in marks) {'student_id': m.studentId, 'is_present': m.isPresent},
          ],
        });
      });

  /// GET /attendance/batch/:id/daily?date=YYYY-MM-DD — full roster with
  /// eligibility flags.
  Future<List<AttendanceEntry>> daily({required String batchId, required DateTime date}) =>
      guard(() async => Parse.dailyRoster(
          (await _dio.get('/attendance/batch/$batchId/daily',
                  queryParameters: {'date': _ymd(date)}))
              .data));

  /// GET /attendance/batch/:id/history?limit=N — last-N sessions per student.
  Future<Map<String, List<AttendanceHistoryEntry>>> batchHistory(String batchId, {int limit = 5}) =>
      guard(() async => Parse.batchHistory(
          (await _dio.get('/attendance/batch/$batchId/history',
                  queryParameters: {'limit': limit}))
              .data));

  /// GET /attendance/batch/:id/student/:sid/history — full log for one student.
  Future<List<AttendanceHistoryEntry>> studentHistory({
    required String batchId,
    required String studentId,
  }) =>
      guard(() async => Parse.historyList(
          (await _dio.get('/attendance/batch/$batchId/student/$studentId/history')).data));

  /// GET /attendance/batch/:id/pending-remarks — absent rows missing a reason.
  Future<List<PendingRemark>> batchPendingRemarks(String batchId) =>
      guard(() async => Parse.batchPendingRemarks(
          (await _dio.get('/attendance/batch/$batchId/pending-remarks')).data));

  // ── Reports ─────────────────────────────────────────────────────────────
  /// GET /attendance/reports/overall.
  Future<OverallAttendanceReport> overall({
    required DateTime start,
    required DateTime end,
    String? locationId,
  }) =>
      guard(() async => Parse.overallReport(
          (await _dio.get('/attendance/reports/overall',
                  queryParameters: _range(start, end, locationId)))
              .data));

  /// GET /attendance/today-summary — lightweight KPI (`null` when no batch runs).
  Future<double?> todaySummary({String? locationId}) =>
      guard(() async => Parse.todayAttendancePercentage(
          (await _dio.get('/attendance/today-summary',
                  queryParameters: locationId == null ? null : {'location_id': locationId}))
              .data));

  /// GET /attendance/reports/compliance.
  Future<ComplianceReport> compliance({
    required DateTime start,
    required DateTime end,
    String? locationId,
  }) =>
      guard(() async => Parse.complianceReport(
          (await _dio.get('/attendance/reports/compliance',
                  queryParameters: _range(start, end, locationId)))
              .data));

  /// GET /attendance/reports/faculty/:id.
  Future<FacultyAttendanceReport> facultyReport({
    required String facultyId,
    required DateTime start,
    required DateTime end,
    String? locationId,
  }) =>
      guard(() async => Parse.facultyReport(
          (await _dio.get('/attendance/reports/faculty/$facultyId',
                  queryParameters: _range(start, end, locationId)))
              .data));

  /// GET /attendance/reports/batch/:id.
  Future<BatchAttendanceReport> batchReport({
    required String batchId,
    required DateTime start,
    required DateTime end,
  }) =>
      guard(() async => Parse.batchReport(
          (await _dio.get('/attendance/reports/batch/$batchId',
                  queryParameters: {'startDate': _ymd(start), 'endDate': _ymd(end)}))
              .data));

  // ── Absent remarks (Feature 4) ──────────────────────────────────────────
  /// PATCH /attendance/remarks — set the reason/comment on one absent record.
  Future<void> updateRemark({
    required String attendanceId,
    String? absentReason,
    String? followUpComment,
  }) =>
      guard(() async {
        await _dio.patch('/attendance/remarks', data: {
          'attendance_id': attendanceId,
          if (absentReason != null) 'absent_reason': absentReason,
          if (followUpComment != null) 'follow_up_comment': followUpComment,
        });
      });

  /// GET /attendance/pending-remarks/batches?date= — pending grouped by batch.
  //
  // NOTE: the flat GET /attendance/pending-remarks (no /batches) is intentionally
  // NOT wired — it returns the same absent-without-reason records this grouped
  // endpoint does, just ungrouped. The staff UI only needs the grouped view, so
  // the grouped superset is the single source of truth for the pending queue.
  Future<List<PendingRemarksGroup>> pendingRemarksByBatch({required DateTime date}) =>
      guard(() async => Parse.pendingRemarksGroups(
          (await _dio.get('/attendance/pending-remarks/batches',
                  queryParameters: {'date': _ymd(date)}))
              .data));

  Map<String, dynamic> _range(DateTime s, DateTime e, String? loc) => {
        'startDate': _ymd(s),
        'endDate': _ymd(e),
        if (loc != null) 'location_id': loc,
      };

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

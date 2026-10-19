import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../dio_executor.dart';

/// Role work that the Scheduler serves today:
///   GET  /api/batches                                   (faculty sees own; filtered server-side)
///   GET  /api/attendance/batch/:batchId/daily?date=     (marking roster)
///   POST /api/attendance                                (upsert the day's marks)
///   GET  /api/interviews/mine/upcoming                  (panel member's next 24h)
class WorkRemoteDataSource with DioExecutor {
  WorkRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<TeamBatch>> batches() => guard(() async {
        final res = await _dio.get('/batches');
        final list = (res.data as List?) ?? const [];
        return list
            .whereType<Map>()
            .map((e) => TeamBatch.fromJson(e.cast<String, dynamic>()))
            .toList();
      });

  Future<List<AttendanceStudent>> dailyAttendance(String batchId, String date) => guard(() async {
        final res = await _dio.get('/attendance/batch/$batchId/daily', queryParameters: {'date': date});
        final list = (res.data as List?) ?? const [];
        return list
            .whereType<Map>()
            .map((e) => AttendanceStudent.fromJson(e.cast<String, dynamic>()))
            .toList();
      });

  Future<void> markAttendance({
    required String batchId,
    required String date,
    required Map<String, bool> present,
  }) =>
      guard(() => _dio.post('/attendance', data: {
            'batchId': batchId,
            'date': date,
            'attendance': [
              for (final entry in present.entries)
                {'student_id': entry.key, 'is_present': entry.value},
            ],
          }));

  Future<List<InterviewRound>> upcomingInterviews() => guard(() async {
        final res = await _dio.get('/interviews/mine/upcoming');
        final data = (res.data as Map).cast<String, dynamic>();
        return ((data['interviews'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => InterviewRound.fromJson(e.cast<String, dynamic>()))
            .toList();
      });

  /// The full interview calendar the caller may see (`GET /api/interviews`).
  Future<List<InterviewRound>> interviews() => guard(() async {
        final res = await _dio.get('/interviews');
        final data = (res.data as Map).cast<String, dynamic>();
        return ((data['interviews'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => InterviewRound.fromJson(e.cast<String, dynamic>()))
            .toList();
      });

  /// `POST /api/interviews/:roundId/outcome` — { outcome, remarks }.
  Future<void> recordOutcome(String roundId, {required String outcome, required String remarks}) =>
      guard(() => _dio.post('/interviews/$roundId/outcome', data: {'outcome': outcome, 'remarks': remarks}));

  /// `POST /api/interviews/:roundId/postpone` — { proposed_at, reason }.
  Future<void> postponeInterview(String roundId, {required DateTime proposedAt, required String reason}) =>
      guard(() => _dio.post('/interviews/$roundId/postpone', data: {
            'proposed_at': proposedAt.toUtc().toIso8601String(),
            'reason': reason,
          }));

  /// Absent-student remark (`PATCH /api/attendance/remarks`).
  Future<void> updateAbsentRemarks({
    required String attendanceId,
    String? absentReason,
    String? followUpComment,
  }) =>
      guard(() => _dio.patch('/attendance/remarks', data: {
            'attendance_id': attendanceId,
            'absent_reason': absentReason,
            'follow_up_comment': followUpComment,
          }));

  /// Faculty indicators (`GET /api/attendance/reports/faculty/:id`).
  Future<FacultyReport> facultyReport(String facultyId, {required String startDate, required String endDate}) =>
      guard(() async {
        final res = await _dio.get('/attendance/reports/faculty/$facultyId',
            queryParameters: {'startDate': startDate, 'endDate': endDate});
        return FacultyReport.fromJson((res.data as Map).cast<String, dynamic>());
      });
}

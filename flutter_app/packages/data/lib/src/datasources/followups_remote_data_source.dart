import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler follow-up task management over the Bearer-JWT Dio. Reads auto-scope
/// to the caller's branch; the create-log write is gated server-side by
/// denyWrite (accounts_admin read-only).
class FollowUpsRemoteDataSource with DioExecutor {
  FollowUpsRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /follow-ups — task worklist + tab counts. [dateFilter] ∈
  /// today|overdue|upcoming (null = all).
  Future<FollowUpTasksPage> tasks({String? dateFilter, String? searchTerm, String? locationId}) =>
      guard(() async => Parse.followUpTasks((await _dio.get('/follow-ups', queryParameters: {
            if (dateFilter != null) 'dateFilter': dateFilter,
            if (searchTerm != null && searchTerm.isNotEmpty) 'searchTerm': searchTerm,
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// GET /follow-ups/staff-report — per-staff activity over a date range.
  Future<StaffFollowUpReport> staffReport({
    required DateTime start,
    required DateTime end,
    String? locationId,
  }) =>
      guard(() async => Parse.staffFollowUpReport((await _dio.get('/follow-ups/staff-report', queryParameters: {
            'startDate': _ymd(start),
            'endDate': _ymd(end),
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// GET /follow-ups/history/:admissionId — log history for one admission.
  Future<List<FollowUpLog>> history(String admissionId) =>
      guard(() async => Parse.followUpLogs((await _dio.get('/follow-ups/history/$admissionId')).data));

  /// POST /follow-ups — log a manual follow-up.
  Future<void> createLog(FollowUpLogDraft draft) => guard(() async {
        await _dio.post('/follow-ups', data: draft.toJson());
      });

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

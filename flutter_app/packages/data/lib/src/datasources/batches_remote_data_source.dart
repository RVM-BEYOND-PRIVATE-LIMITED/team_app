import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler batch console over the Bearer-JWT Dio. Reads are auto-scoped to the
/// caller's branch (super-admin may pass [locationId]/'all'); writes are gated
/// server-side by denyWrite (accounts_admin is read-only).
class BatchesRemoteDataSource with DioExecutor {
  BatchesRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /batches — optional faculty/date-range filters.
  Future<List<StaffBatch>> list({
    String? facultyId,
    String? locationId,
    DateTime? startDate,
    DateTime? endDate,
  }) =>
      guard(() async => Parse.staffBatches((await _dio.get('/batches', queryParameters: {
            if (facultyId != null) 'facultyId': facultyId,
            if (locationId != null) 'location_id': locationId,
            if (startDate != null) 'startDate': _ymd(startDate),
            if (endDate != null) 'endDate': _ymd(endDate),
          }))
              .data));

  /// GET /batches/active-students-count — header KPI.
  Future<ActiveStudentsCount> activeStudentsCount({String? locationId}) =>
      guard(() async => Parse.activeStudentsCount((await _dio.get(
            '/batches/active-students-count',
            queryParameters: locationId == null ? null : {'location_id': locationId},
          ))
              .data));

  /// GET /batches/:id/students — roster with dues + risk flags.
  Future<List<BatchStudent>> students(String batchId) =>
      guard(() async => Parse.batchStudents((await _dio.get('/batches/$batchId/students')).data));

  /// POST /batches — returns the created batch.
  Future<StaffBatch> create(BatchDraft draft) =>
      guard(() async => Parse.staffBatch(asMap((await _dio.post('/batches', data: draft.toJson())).data)));

  /// PUT /batches/:id — returns the updated batch.
  Future<StaffBatch> update(String batchId, BatchDraft draft) => guard(
      () async => Parse.staffBatch(asMap((await _dio.put('/batches/$batchId', data: draft.toJson())).data)));

  /// DELETE /batches/:id — 204 No Content.
  Future<void> delete(String batchId) => guard(() async {
        await _dio.delete('/batches/$batchId');
      });

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

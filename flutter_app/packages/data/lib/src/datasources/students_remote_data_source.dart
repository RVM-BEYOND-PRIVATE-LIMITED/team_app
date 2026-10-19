import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler student master over the Bearer-JWT Dio. Reads auto-scope to the
/// caller's branch (super-admin may pass [locationId]/'all'); writes are gated
/// server-side (denyWrite for accounts_admin; defaulter/hold are admin/super
/// only, enforced again by the app's permission flags).
class StudentsRemoteDataSource with DioExecutor {
  StudentsRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /students — paginated + searchable, with on-hold / fee-pending filters.
  Future<StudentsPage> list({
    String? search,
    String? locationId,
    int page = 1,
    int limit = 20,
    bool onHold = false,
    bool feePending = false,
  }) =>
      guard(() async => Parse.studentsPage((await _dio.get('/students', queryParameters: {
            'page': page,
            'limit': limit,
            if (search != null && search.isNotEmpty) 'search': search,
            if (locationId != null) 'location_id': locationId,
            if (onHold) 'on_hold': 'true',
            if (feePending) 'fee_pending': 'true',
          }))
              .data));

  /// GET /students/:id/batches → `{batches:[...]}`.
  Future<List<StaffBatch>> batches(String studentId) =>
      guard(() async => Parse.studentBatchList((await _dio.get('/students/$studentId/batches')).data));

  /// GET /students/:id/defaulter → current defaulter status.
  Future<DefaulterStatus> defaulterStatus(String studentId) =>
      guard(() async => Parse.defaulterStatus((await _dio.get('/students/$studentId/defaulter')).data));

  /// POST /students — returns the created student row.
  Future<StaffStudent> create(StudentDraft draft) =>
      guard(() async => Parse.staffStudentOf(asMap((await _dio.post('/students', data: draft.toJson())).data)));

  /// PUT /students/:id — returns the updated student row.
  Future<StaffStudent> update(String id, StudentDraft draft) => guard(
      () async => Parse.staffStudentOf(asMap((await _dio.put('/students/$id', data: draft.toJson())).data)));

  /// DELETE /students/:id — 204 No Content.
  Future<void> delete(String id) => guard(() async {
        await _dio.delete('/students/$id');
      });

  /// PUT /students/:id/transfer — move the student to another branch.
  Future<void> transfer({required String id, required int newLocationId}) => guard(() async {
        await _dio.put('/students/$id/transfer', data: {'new_location_id': newLocationId});
      });

  /// POST /students/:id/mark-defaulter — admin/super only.
  Future<void> markDefaulter({required String id, String? reason}) => guard(() async {
        await _dio.post('/students/$id/mark-defaulter',
            data: {'is_defaulter': true, if (reason != null) 'reason': reason});
      });

  /// POST /students/:id/remove-defaulter — admin/super only.
  Future<void> removeDefaulter(String id) => guard(() async {
        await _dio.post('/students/$id/remove-defaulter');
      });

  /// POST /students/:id/hold — admin/super only; category + remarks (≥5 chars).
  Future<void> hold({required String id, required String category, required String remarks}) =>
      guard(() async {
        await _dio.post('/students/$id/hold',
            data: {'hold_category': category, 'hold_remarks': remarks});
      });

  /// POST /students/:id/unhold — admin/super only.
  Future<void> unhold(String id) => guard(() async {
        await _dio.post('/students/$id/unhold');
      });
}

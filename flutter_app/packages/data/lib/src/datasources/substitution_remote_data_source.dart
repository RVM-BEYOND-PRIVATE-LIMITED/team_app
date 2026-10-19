import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler faculty substitution over the Bearer-JWT Dio. All endpoints are
/// admin-gated server-side (admin middleware) — the app also restricts the
/// destination to admin + super_admin.
class SubstitutionRemoteDataSource with DioExecutor {
  SubstitutionRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /substitution/temporary — active (not-yet-ended) substitutions.
  Future<List<Substitution>> list({String? locationId}) =>
      guard(() async => Parse.substitutions((await _dio.get('/substitution/temporary',
              queryParameters: locationId == null ? null : {'location_id': locationId}))
          .data));

  /// POST /substitution/temporary — schedule a temporary substitution.
  Future<void> create(SubstitutionDraft draft) => guard(() async {
        await _dio.post('/substitution/temporary', data: draft.toJson());
      });

  /// PUT /substitution/temporary/:id — edit a substitution.
  Future<void> update(String id, SubstitutionUpdate update) => guard(() async {
        await _dio.put('/substitution/temporary/$id', data: update.toJson());
      });

  /// DELETE /substitution/temporary/:id — cancel a substitution.
  Future<void> cancel(String id) => guard(() async {
        await _dio.delete('/substitution/temporary/$id');
      });

  /// POST /substitution/assign — permanently reassign a batch's faculty.
  Future<void> assign({required String batchId, required String facultyId}) => guard(() async {
        await _dio.post('/substitution/assign', data: {'batchId': batchId, 'facultyId': facultyId});
      });

  /// POST /substitution/merge — merge one batch into another.
  Future<void> merge({required String sourceBatchId, required String targetBatchId}) => guard(() async {
        await _dio.post('/substitution/merge',
            data: {'sourceBatchId': sourceBatchId, 'targetBatchId': targetBatchId});
      });
}

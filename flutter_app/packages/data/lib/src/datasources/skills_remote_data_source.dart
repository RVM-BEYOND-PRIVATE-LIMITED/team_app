import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler skill catalog over the Bearer-JWT Dio. Reads are branch-scoped
/// (super-admin may pass [locationId]); create/update/delete require admin. A
/// duplicate name at a location 409s.
class SkillsRemoteDataSource with DioExecutor {
  SkillsRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /skills — the branch's skills.
  Future<List<Skill>> list({String? locationId}) =>
      guard(() async => Parse.skills((await _dio.get('/skills', queryParameters: {
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// POST /skills — returns the created row.
  Future<Skill> create(SkillDraft draft) =>
      guard(() async => Parse.skillOf((await _dio.post('/skills', data: draft.toJson())).data));

  /// PUT /skills/:id — returns the updated row.
  Future<Skill> update(String id, SkillDraft draft) =>
      guard(() async => Parse.skillOf((await _dio.put('/skills/$id', data: draft.toJson())).data));

  /// DELETE /skills/:id — 204 No Content.
  Future<void> delete(String id) => guard(() async {
        await _dio.delete('/skills/$id');
      });
}

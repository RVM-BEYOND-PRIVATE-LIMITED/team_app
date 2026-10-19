import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler certificate catalog over the Bearer-JWT Dio. The reads are public
/// server-side; the create/update/delete writes require admin (super or branch
/// admin), gated again by the app's permission flags. A duplicate name 409s.
class CertificatesRemoteDataSource with DioExecutor {
  CertificatesRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /certificates — all certificates, sorted by name.
  Future<List<Certificate>> list() =>
      guard(() async => Parse.certificates((await _dio.get('/certificates')).data));

  /// GET /certificates/:id — a single certificate (fresh, e.g. before editing).
  Future<Certificate> byId(String id) =>
      guard(() async => Parse.certificateOf((await _dio.get('/certificates/$id')).data));

  /// POST /certificates — returns the created row (unwrapped from `{certificate}`).
  Future<Certificate> create(CertificateDraft draft) => guard(
      () async => Parse.certificateOf((await _dio.post('/certificates', data: draft.toJson())).data));

  /// PUT /certificates/:id — returns the updated row.
  Future<Certificate> update(String id, CertificateDraft draft) => guard(
      () async => Parse.certificateOf((await _dio.put('/certificates/$id', data: draft.toJson())).data));

  /// DELETE /certificates/:id — returns `{message}`, ignored.
  Future<void> delete(String id) => guard(() async {
        await _dio.delete('/certificates/$id');
      });
}

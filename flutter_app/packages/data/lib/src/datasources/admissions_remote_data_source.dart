import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler admissions over the Bearer-JWT Dio. Reads auto-scope to the
/// caller's branch (super-admin may pass a location). Dropout is super-admin
/// only; reactivate + toggle-undertaking need branch write (denyWrite). Create
/// + update are intentionally NOT wired here yet — they take courses +
/// installments + certificate ids and land with those modules.
class AdmissionsRemoteDataSource with DioExecutor {
  AdmissionsRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /admissions — metrics header + enriched rows (optional search).
  Future<AdmissionsPage> list({String? search, String? locationId}) =>
      guard(() async => Parse.admissionsPage((await _dio.get('/admissions', queryParameters: {
            if (search != null && search.isNotEmpty) 'search': search,
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// GET /admissions/:id — single admission with courses + installments.
  Future<AdmissionDetail> byId(String id) =>
      guard(() async => Parse.admissionDetail((await _dio.get('/admissions/$id')).data));

  /// GET /admissions/by-phone/:phone — intake lookup (existing vs new).
  Future<AdmissionPhoneCheck> byPhone(String phone) =>
      guard(() async => Parse.admissionPhoneCheck((await _dio.get('/admissions/by-phone/$phone')).data));

  /// GET /admissions/dropout-registry — formally dropped-out students.
  Future<List<AdmissionRow>> dropoutRegistry({String? search, String? locationId, String? from, String? to}) =>
      guard(() async => Parse.dropoutRegistry((await _dio.get('/admissions/dropout-registry', queryParameters: {
            if (search != null && search.isNotEmpty) 'search': search,
            if (locationId != null) 'location_id': locationId,
            if (from != null) 'from': from,
            if (to != null) 'to': to,
          }))
              .data));

  /// PUT /admissions/:id/dropout — super-admin only.
  Future<void> markDropout({required String id, String? reason}) => guard(() async {
        await _dio.put('/admissions/$id/dropout', data: {if (reason != null) 'dropout_reason': reason});
      });

  /// PUT /admissions/:id/reactivate — restore a dropout.
  Future<void> reactivate(String id) => guard(() async {
        await _dio.put('/admissions/$id/reactivate');
      });

  /// PUT /admissions/:id/toggle-undertaking — set the undertaking done flag.
  Future<void> toggleUndertaking({required String id, required bool completed}) => guard(() async {
        await _dio.put('/admissions/$id/toggle-undertaking', data: {'completed': completed});
      });
}

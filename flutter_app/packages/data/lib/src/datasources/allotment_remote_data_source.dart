import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler batch-allotment over the Bearer-JWT Dio. Reads auto-scope to the
/// caller's branch; the update + follow-up writes are gated server-side by
/// denyWrite (accounts_admin read-only).
class AllotmentRemoteDataSource with DioExecutor {
  AllotmentRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /batch-allotment — the allotment worklist.
  Future<List<AllotmentRow>> list({String? search, String? locationId}) =>
      guard(() async => Parse.allotmentRows((await _dio.get('/batch-allotment', queryParameters: {
            if (search != null && search.isNotEmpty) 'search': search,
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// PUT /batch-allotment/:admissionId — set joined / joining date / remarks.
  Future<void> update(String admissionId, AllotmentUpdate update) => guard(() async {
        await _dio.put('/batch-allotment/$admissionId', data: update.toJson());
      });

  /// GET /batch-allotment/history/:admissionId — remark history.
  Future<List<AdmissionRemark>> remarkHistory(String admissionId) =>
      guard(() async => Parse.remarkHistory((await _dio.get('/batch-allotment/history/$admissionId')).data));

  /// GET /batch-allotment/follow-ups/:admissionId — follow-up log.
  Future<FollowUpHistory> followUps(String admissionId) => guard(
      () async => Parse.followUpHistory((await _dio.get('/batch-allotment/follow-ups/$admissionId')).data));

  /// POST /batch-allotment/follow-ups/:admissionId — log a follow-up.
  Future<FollowUp> createFollowUp(String admissionId, FollowUpDraft draft) => guard(() async =>
      Parse.followUpOf((await _dio.post('/batch-allotment/follow-ups/$admissionId', data: draft.toJson())).data));

  /// GET /batch-allotment/red-students — at-risk students.
  Future<List<RedFlagStudent>> redStudents({String? search, String? locationId}) =>
      guard(() async => Parse.redStudents((await _dio.get('/batch-allotment/red-students', queryParameters: {
            if (search != null && search.isNotEmpty) 'search': search,
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// GET /batch-allotment/red-flag-summary — count + per-student summary.
  Future<RedFlagSummary> redFlagSummary({String? locationId}) => guard(() async => Parse.redFlagSummary(
      (await _dio.get('/batch-allotment/red-flag-summary',
              queryParameters: locationId == null ? null : {'location_id': locationId}))
          .data));
}

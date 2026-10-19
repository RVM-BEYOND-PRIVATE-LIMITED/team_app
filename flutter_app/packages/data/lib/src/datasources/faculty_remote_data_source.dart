import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler faculty (HR) over the Bearer-JWT Dio. Reads auto-scope to the
/// caller's branch; create/update/delete are gated server-side by denyWrite.
class FacultyRemoteDataSource with DioExecutor {
  FacultyRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /faculty — roster with skills + availability + leave/status.
  Future<List<Faculty>> list({String? locationId}) =>
      guard(() async => Parse.faculties((await _dio.get('/faculty',
              queryParameters: locationId == null ? null : {'location_id': locationId}))
          .data));

  /// GET /faculty/active-students → `{facultyId: activeCount}`.
  Future<Map<String, int>> activeStudents({String? locationId}) =>
      guard(() async => Parse.facultyActiveStudents((await _dio.get('/faculty/active-students',
              queryParameters: locationId == null ? null : {'location_id': locationId}))
          .data));

  /// GET /faculty/student-counts → `{facultyId: totalCount}`.
  Future<Map<String, int>> studentCounts({String? locationId}) =>
      guard(() async => Parse.facultyStudentCounts((await _dio.get('/faculty/student-counts',
              queryParameters: locationId == null ? null : {'location_id': locationId}))
          .data));

  /// GET /faculty/total-students/:id — all-time distinct student ids.
  Future<FacultyTotalStudents> totalStudents(String facultyId) => guard(() async =>
      Parse.facultyTotalStudents((await _dio.get('/faculty/total-students/$facultyId')).data));

  /// POST /faculty — link an existing user as faculty.
  Future<Faculty> create(FacultyDraft draft) =>
      guard(() async => Parse.facultyOf(asMap((await _dio.post('/faculty', data: draft.toJson())).data)));

  /// PUT /faculty/:id — returns the updated faculty.
  Future<Faculty> update(String id, FacultyUpdate update) => guard(
      () async => Parse.facultyOf(asMap((await _dio.put('/faculty/$id', data: update.toJson())).data)));

  /// DELETE /faculty/:id — 204 (400 if the faculty still owns batches).
  Future<void> delete(String id) => guard(() async {
        await _dio.delete('/faculty/$id');
      });

  // ── Availability (/availability) ────────────────────────────────────────
  /// GET /availability/faculty/:id — the faculty's weekly slots.
  Future<List<FacultyAvailability>> availability(String facultyId) => guard(() async =>
      Parse.availabilitySlots((await _dio.get('/availability/faculty/$facultyId')).data));

  /// POST /availability — replace the faculty's weekly availability. Returns the
  /// updated slots (409 if it conflicts with the faculty's existing batches).
  Future<List<FacultyAvailability>> setAvailability({
    required String facultyId,
    required List<FacultyAvailability> slots,
  }) =>
      guard(() async => Parse.availabilitySlots((await _dio.post('/availability', data: {
            'facultyId': facultyId,
            'availability': [
              for (final s in slots)
                {'day_of_week': s.dayOfWeek, 'start_time': s.startTime, 'end_time': s.endTime},
            ],
          }))
              .data));
}

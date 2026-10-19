import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../dio_executor.dart';

/// Faculty Development (HOD) surfaces that exist in the Scheduler today:
///   GET   /api/hod/overview?month=YYYY-MM       (facultyDevDashboardController)
///   GET   /api/hod/interviews                   (interview_log rows)
///   PATCH /api/hod/interviews/:id/verdict       { verdict, feedback }
///   GET   /api/hod/roster/faculty-options       (roster + unrostered)
///   POST  /api/hod/risk-logs                    { faculty_id|faculty_name, ... }
///   POST  /api/faculty-comments                 { faculty_id, comment }
class HodRemoteDataSource with DioExecutor {
  HodRemoteDataSource(this._dio);

  final Dio _dio;

  Future<HodOverview> overview({String? month}) => guard(() async {
        final res = await _dio.get('/hod/overview', queryParameters: {if (month != null) 'month': month});
        return HodOverview.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<List<HodInterview>> interviews() => guard(() async {
        final res = await _dio.get('/hod/interviews');
        final data = (res.data as Map).cast<String, dynamic>();
        return ((data['rows'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => HodInterview.fromJson(e.cast<String, dynamic>()))
            .toList();
      });

  Future<void> setVerdict(String id, {required String verdict, required String feedback}) => guard(
        () => _dio.patch('/hod/interviews/$id/verdict', data: {'verdict': verdict, 'feedback': feedback}),
      );

  Future<List<FacultyOption>> facultyOptions() => guard(() async {
        final res = await _dio.get('/hod/roster/faculty-options');
        final data = (res.data as Map).cast<String, dynamic>();
        final out = <FacultyOption>[];
        for (final key in const ['roster', 'unrostered']) {
          for (final e in (data[key] as List?) ?? const []) {
            if (e is Map) out.add(FacultyOption.fromJson(e.cast<String, dynamic>()));
          }
        }
        return out;
      });

  Future<void> createRiskLog({
    required String facultyId,
    String? facultyName,
    String? logDate,
    String entryType = 'one_on_one',
    String riskLevel = 'none',
    String? signal,
    String? actionTaken,
    bool escalated = false,
  }) =>
      guard(() => _dio.post('/hod/risk-logs', data: {
            'faculty_id': facultyId,
            if (facultyName != null) 'faculty_name': facultyName,
            if (logDate != null) 'log_date': logDate,
            'entry_type': entryType,
            'risk_level': riskLevel,
            if (signal != null) 'signal': signal,
            if (actionTaken != null) 'action_taken': actionTaken,
            'escalated': escalated,
          }));

  Future<void> createFacultyComment({required String facultyId, required String comment}) => guard(
        () => _dio.post('/faculty-comments', data: {'faculty_id': facultyId, 'comment': comment}),
      );
}

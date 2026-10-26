import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../dio_executor.dart';

/// Role work that the Scheduler still serves:
///   GET  /api/batches                                   (faculty sees own; filtered server-side)
///   GET  /api/interviews/mine/upcoming                  (panel member's next 24h)
/// Class marking moved to the ESS (H1); this client no longer writes attendance.
class WorkRemoteDataSource with DioExecutor {
  WorkRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<TeamBatch>> batches() => guard(() async {
        final res = await _dio.get('/batches');
        final list = (res.data as List?) ?? const [];
        return list
            .whereType<Map>()
            .map((e) => TeamBatch.fromJson(e.cast<String, dynamic>()))
            .toList();
      });

  Future<List<InterviewRound>> upcomingInterviews() async {
    try {
      final res = await _dio.get('/interviews/mine/upcoming',
          options: Options(validateStatus: (_) => true));
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return const [];
      final data = (res.data as Map).cast<String, dynamic>();
      return ((data['interviews'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => InterviewRound.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      // The Home card is optional; a refusal hides it rather than surfacing a
      // thrown exception on the first screen.
      return const [];
    }
  }

  /// The full interview calendar the caller may see (`GET /api/interviews`).
  ///
  /// A 403 here is not an error: the Scheduler answers 403
  /// (`INTERVIEWS_ACCESS_DENIED`) to any authenticated caller who is neither a
  /// blanket role nor on a panel — e.g. a plain `admin`. The sibling
  /// `mine/upcoming` endpoint already answers those callers with an empty
  /// list ("not being on a panel is not an error"), so this does the same:
  /// empty calendar, never a crash, for every role and in every condition.
  Future<List<InterviewRound>> interviews() async {
    try {
      return await guard(() async {
        final res = await _dio.get('/interviews');
        final data = (res.data as Map).cast<String, dynamic>();
        return ((data['interviews'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => InterviewRound.fromJson(e.cast<String, dynamic>()))
            .toList();
      });
    } on ForbiddenFailure {
      return const [];
    }
  }

  /// `POST /api/interviews/:roundId/outcome` — { outcome, remarks }.
  Future<void> recordOutcome(String roundId,
          {required String outcome, required String remarks}) =>
      guard(() => _dio.post('/interviews/$roundId/outcome',
          data: {'outcome': outcome, 'remarks': remarks}));

  /// `POST /api/interviews/:roundId/postpone` — { proposed_at, reason }.
  Future<void> postponeInterview(String roundId,
          {required DateTime proposedAt, required String reason}) =>
      guard(() => _dio.post('/interviews/$roundId/postpone', data: {
            'proposed_at': proposedAt.toUtc().toIso8601String(),
            'reason': reason,
          }));

  /// Faculty indicators (`GET /api/attendance/reports/faculty/:id`).
  Future<FacultyReport> facultyReport(String facultyId,
          {required String startDate, required String endDate}) =>
      guard(() async {
        final res = await _dio.get('/attendance/reports/faculty/$facultyId',
            queryParameters: {'startDate': startDate, 'endDate': endDate});
        return FacultyReport.fromJson(
            (res.data as Map).cast<String, dynamic>());
      });
}

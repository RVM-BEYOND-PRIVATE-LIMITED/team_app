import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

import '../../domain/attendance_models.dart';
import '../dio_executor.dart';

/// The Scheduler's own punch path (`/api/hr/my-attendance`). The device cookie
/// (`rvm_att_dev`) and the mobile User-Agent are set on the Scheduler Dio, so
/// these calls carry them automatically (tasks B8/B13).
class MyAttendanceRemoteDataSource with DioExecutor {
  MyAttendanceRemoteDataSource(this._dio);

  final Dio _dio;

  /// Expected refusals on this path (a 409 cooldown, an already-punched-in
  /// state, a 403 device rule) are results the screen must render, not a
  /// DioException the debugger stops on. Returning them as a normal Response
  /// lets [DioExecutor.guard] turn them into the typed Failure the blocs
  /// already handle. 401 still throws so the bearer interceptor ends the
  /// session.
  Options _readOptions() => Options(
      validateStatus: (status) => status != null && status != 401);

  Future<MyAttendance> myAttendance({String? month}) async {
    final res = await guard<Response<dynamic>>(() => _dio.get(
          '/hr/my-attendance',
          queryParameters: {if (month != null) 'month': month},
          options: _readOptions(),
        ));
    return MyAttendance.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// The Home/schedule read without throwing for a 401/403/5xx. A portal
  /// token can be refused by the Scheduler's own employee link rules even
  /// though the ESS capabilities passed; that must render a card, not a
  /// DioException the debugger stops on.
  Future<({MyAttendance? data, Failure? failure})> myAttendanceSafe(
      {String? month}) async {
    try {
      final res = await _dio.get(
        '/hr/my-attendance',
        queryParameters: {if (month != null) 'month': month},
        options: Options(validateStatus: (_) => true),
      );
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        return (data: null, failure: failureFromResponse(status, res.data));
      }
      return (
        data: MyAttendance.fromJson((res.data as Map).cast<String, dynamic>()),
        failure: null,
      );
    } on DioException catch (e) {
      return (data: null, failure: Failure.fromDio(e));
    } catch (_) {
      return (
        data: null,
        failure: const UnknownFailure('Could not load your attendance.'),
      );
    }
  }

  Future<PunchChallenge> challenge() async {
    final res = await guard<Response<dynamic>>(
        () => _dio.get('/hr/my-attendance/challenge', options: _readOptions()));
    return PunchChallenge.fromJson(
        (res.data as Map).cast<String, dynamic>());
  }

  Future<PunchAccepted> punch({
    required String kind,
    required String nonce,
    required double latitude,
    required double longitude,
    required double accuracyM,
    DateTime? clientAt,
    String? note,
  }) async {
    final res = await guard<Response<dynamic>>(() =>
        _dio.post('/hr/my-attendance/punch', options: _readOptions(), data: {
          'kind': kind,
          'nonce': nonce,
          'latitude': latitude,
          'longitude': longitude,
          'accuracy_m': accuracyM,
          if (clientAt != null) 'client_at': clientAt.toIso8601String(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        }));
    return PunchAccepted.fromJson(
        (res.data as Map).cast<String, dynamic>());
  }

  Future<void> ping({
    required double latitude,
    required double longitude,
    required double accuracyM,
  }) async {
    await guard<Response<dynamic>>(() =>
        _dio.post('/hr/my-attendance/ping', options: _readOptions(), data: {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy_m': accuracyM,
        }));
  }

  Future<void> saveRemark({required String day, String? remarks}) async {
    await guard<Response<dynamic>>(() => _dio.put('/hr/my-attendance/remarks',
        options: _readOptions(), data: {'day': day, 'remarks': remarks}));
  }

  /// Set/replace the attendance password (first-time password / none yet). The
  /// reply's fresh 30-day token replaces the current session; every older
  /// session of this login stops working.
  Future<String> setAttendancePassword(String password) async {
    final res = await guard<Response<dynamic>>(() => _dio.post(
        '/hr/my-attendance/password',
        options: _readOptions(),
        data: {'password': password}));
    return ((res.data as Map).cast<String, dynamic>()['token']
            as String?) ??
        '';
  }
}

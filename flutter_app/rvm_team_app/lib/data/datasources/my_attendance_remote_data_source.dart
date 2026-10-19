import 'package:dio/dio.dart';

import '../../domain/attendance_models.dart';
import '../dio_executor.dart';

/// The Scheduler's own punch path (`/api/hr/my-attendance`). The device cookie
/// (`rvm_att_dev`) and the mobile User-Agent are set on the Scheduler Dio, so
/// these calls carry them automatically (tasks B8/B13).
class MyAttendanceRemoteDataSource with DioExecutor {
  MyAttendanceRemoteDataSource(this._dio);

  final Dio _dio;

  Future<MyAttendance> myAttendance({String? month}) => guard(() async {
        final res = await _dio.get('/hr/my-attendance', queryParameters: {
          if (month != null) 'month': month,
        });
        return MyAttendance.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<PunchChallenge> challenge() => guard(() async {
        final res = await _dio.get('/hr/my-attendance/challenge');
        return PunchChallenge.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<PunchAccepted> punch({
    required String kind,
    required String nonce,
    required double latitude,
    required double longitude,
    required double accuracyM,
    DateTime? clientAt,
    String? note,
  }) =>
      guard(() async {
        final res = await _dio.post('/hr/my-attendance/punch', data: {
          'kind': kind,
          'nonce': nonce,
          'latitude': latitude,
          'longitude': longitude,
          'accuracy_m': accuracyM,
          if (clientAt != null) 'client_at': clientAt.toIso8601String(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        });
        return PunchAccepted.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<void> ping({
    required double latitude,
    required double longitude,
    required double accuracyM,
  }) =>
      guard(() async {
        await _dio.post('/hr/my-attendance/ping', data: {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy_m': accuracyM,
        });
      });

  Future<void> saveRemark({required String day, String? remarks}) => guard(() async {
        await _dio.put('/hr/my-attendance/remarks', data: {'day': day, 'remarks': remarks});
      });

  /// Set/replace the attendance password (first-time password / none yet). The
  /// reply's fresh 30-day token replaces the current session; every older
  /// session of this login stops working.
  Future<String> setAttendancePassword(String password) => guard(() async {
        final res = await _dio.post('/hr/my-attendance/password', data: {'password': password});
        return ((res.data as Map).cast<String, dynamic>()['token'] as String?) ?? '';
      });
}

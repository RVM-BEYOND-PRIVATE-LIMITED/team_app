import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../../domain/models.dart';
import '../dio_executor.dart';

/// Scheduler sign-in: portal username/phone + password, with optional 2FA, and
/// the code-based password reset.
///   POST /api/users/login
///   POST /api/users/login/verify
///   POST /api/users/forgot-password
///   POST /api/users/forgot-password/confirm
class AuthRemoteDataSource with DioExecutor {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  Future<TeamLoginOutcome> login({
    required String username,
    required String password,
    required String locationName,
  }) =>
      guard(() async {
        final res = await _dio.post('/users/login', data: {
          'username': username,
          'password': password,
          'locationName': locationName,
        });
        final data = (res.data as Map).cast<String, dynamic>();
        if (data['two_factor_required'] == true) {
          return TeamTwoFactorRequired(TeamTwoFactorChallenge.fromJson(data));
        }
        final user = (data['user'] as Map).cast<String, dynamic>();
        return TeamSignedIn(
          token: data['token'] as String,
          identity: StaffIdentity.fromLoginUser(user),
        );
      });

  Future<TeamSignedIn> verifyTwoFactor({
    required String challengeId,
    required String code,
    String? locationName,
  }) =>
      guard(() async {
        final res = await _dio.post('/users/login/verify', data: {
          'challenge_id': challengeId,
          'code': code,
          if (locationName != null) 'location_name': locationName,
        });
        final data = (res.data as Map).cast<String, dynamic>();
        final user = (data['user'] as Map).cast<String, dynamic>();
        return TeamSignedIn(token: data['token'] as String, identity: StaffIdentity.fromLoginUser(user));
      });

  Future<String?> forgotPasswordRequest(String identifier) => guard(() async {
        final res = await _dio.post('/users/forgot-password', data: {'identifier': identifier});
        final data = res.data;
        if (data is Map && data['message'] != null) return data['message'].toString();
        return null;
      });

  Future<void> forgotPasswordConfirm({
    required String identifier,
    required String code,
    required String newPassword,
  }) =>
      guard(() => _dio.post('/users/forgot-password/confirm', data: {
            'identifier': identifier,
            'code': code,
            'new_password': newPassword,
          }));

  // ── Attendance-only sign-in (A2), for staff with no portal login ─────────

  Future<AttendanceLoginResult> attendancePasswordLogin({
    required String identifier,
    required String password,
  }) =>
      guard(() async {
        final res = await _dio.post('/hr/my-attendance/password-login', data: {
          'identifier': identifier,
          'password': password,
        });
        return AttendanceLoginResult.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<AttendanceCodeSent> requestAttendanceCode(String identifier) => guard(() async {
        final res = await _dio.post('/hr/my-attendance/otp/request', data: {'identifier': identifier});
        return AttendanceCodeSent.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<AttendanceLoginResult> verifyAttendanceCode({
    required String challengeId,
    required String code,
  }) =>
      guard(() async {
        final res = await _dio.post('/hr/my-attendance/otp/verify', data: {
          'challenge_id': challengeId,
          'code': code,
        });
        return AttendanceLoginResult.fromJson((res.data as Map).cast<String, dynamic>());
      });
}

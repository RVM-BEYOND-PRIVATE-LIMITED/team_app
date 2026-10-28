import 'package:core_network/core_network.dart';
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

  /// Build the session identity from the token we just received, not only from
  /// the login reply. The Scheduler signs a teaching account's `faculty_id` into
  /// the token as `id` even when the reply's `user` object omits it, which is
  /// what left a fresh install with no faculty link until the app was restarted
  /// (My attendance health, 26 Oct). Fall back to the reply if the token cannot
  /// be decoded.
  StaffIdentity _identity(String token, Map<String, dynamic> user) =>
      StaffIdentity.fromToken(token) ?? StaffIdentity.fromLoginUser(user);

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
          identity: _identity(data['token'] as String, user),
        );
      });

  /// Portal sign-in without throwing for a wrong password / unknown user.
  /// `/users/login` answers 401 for a wrong password; that is an expected
  /// result the login form shows, not an exception the debugger should stop on.
  Future<({TeamLoginOutcome? outcome, Failure? failure})> loginSafe({
    required String username,
    required String password,
    required String locationName,
  }) async {
    try {
      final res = await _dio.post(
        '/users/login',
        data: {
          'username': username,
          'password': password,
          'locationName': locationName,
        },
        // This one request returns 4xx as a value; other calls keep the normal
        // auth/sign-out behaviour.
        options: Options(validateStatus: (_) => true),
      );
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        return (outcome: null, failure: failureFromResponse(status, res.data));
      }
      final data = (res.data as Map).cast<String, dynamic>();
      if (data['two_factor_required'] == true) {
        return (
          outcome: TeamTwoFactorRequired(TeamTwoFactorChallenge.fromJson(data)),
          failure: null,
        );
      }
      final user = (data['user'] as Map).cast<String, dynamic>();
      return (
        outcome: TeamSignedIn(
          token: data['token'] as String,
          identity: _identity(data['token'] as String, user),
        ),
        failure: null,
      );
    } on DioException catch (e) {
      return (outcome: null, failure: Failure.fromDio(e));
    } catch (_) {
      return (
        outcome: null,
        failure: const UnknownFailure('Could not sign in. Try again.'),
      );
    }
  }

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
        return TeamSignedIn(
            token: data['token'] as String,
            identity: _identity(data['token'] as String, user));
      });

  Future<String?> forgotPasswordRequest(String identifier) => guard(() async {
        final res = await _dio
            .post('/users/forgot-password', data: {'identifier': identifier});
        final data = res.data;
        if (data is Map && data['message'] != null) {
          return data['message'].toString();
        }
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
        return AttendanceLoginResult.fromJson(
            (res.data as Map).cast<String, dynamic>());
      });

  Future<AttendanceCodeSent> requestAttendanceCode(String identifier) =>
      guard(() async {
        final res = await _dio.post('/hr/my-attendance/otp/request',
            data: {'identifier': identifier});
        return AttendanceCodeSent.fromJson(
            (res.data as Map).cast<String, dynamic>());
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
        return AttendanceLoginResult.fromJson(
            (res.data as Map).cast<String, dynamic>());
      });
}

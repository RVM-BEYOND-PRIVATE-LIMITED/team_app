import 'package:core_network/core_network.dart';

import '../connectivity_guard.dart';
import '../datasources/auth_remote_data_source.dart';
import '../../domain/models.dart';

/// Sign-in / 2FA / password reset. Fails fast when offline.
class AuthRepository with ConnectivityGuard {
  AuthRepository({required AuthRemoteDataSource remote, required this.connectivity}) : _remote = remote;

  final AuthRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<TeamLoginOutcome> login({
    required String username,
    required String password,
    required String locationName,
  }) async {
    await ensureOnline();
    return _remote.login(username: username, password: password, locationName: locationName);
  }

  Future<TeamSignedIn> verifyTwoFactor({
    required String challengeId,
    required String code,
    String? locationName,
  }) async {
    await ensureOnline();
    return _remote.verifyTwoFactor(challengeId: challengeId, code: code, locationName: locationName);
  }

  Future<String?> forgotPasswordRequest(String identifier) async {
    await ensureOnline();
    return _remote.forgotPasswordRequest(identifier);
  }

  Future<void> forgotPasswordConfirm({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    await ensureOnline();
    return _remote.forgotPasswordConfirm(identifier: identifier, code: code, newPassword: newPassword);
  }

  // ── Attendance-only sign-in (A2) ────────────────────────────────────────

  Future<AttendanceLoginResult> attendancePasswordLogin({
    required String identifier,
    required String password,
  }) async {
    await ensureOnline();
    return _remote.attendancePasswordLogin(identifier: identifier, password: password);
  }

  Future<AttendanceCodeSent> requestAttendanceCode(String identifier) async {
    await ensureOnline();
    return _remote.requestAttendanceCode(identifier);
  }

  Future<AttendanceLoginResult> verifyAttendanceCode({
    required String challengeId,
    required String code,
  }) async {
    await ensureOnline();
    return _remote.verifyAttendanceCode(challengeId: challengeId, code: code);
  }
}

import 'package:core_network/core_network.dart';

import '../datasources/staff_auth_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff login/reset. Fails fast with [NoConnectionFailure] when offline; other
/// data-source [Failure]s (401 bad creds, 429 rate-limit, 5xx …) propagate.
class StaffAuthRepository with ConnectivityGuard {
  StaffAuthRepository({required StaffAuthRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final StaffAuthRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  /// A session, or a [StaffTwoFactorChallenge] for an account with 2FA on.
  Future<StaffLoginOutcome> login({
    required String username,
    required String password,
    required String locationName,
  }) async {
    await ensureOnline();
    return _remote.login(username: username, password: password, locationName: locationName);
  }

  Future<StaffSignedIn> verifyTwoFactor({
    required String challengeId,
    required String code,
    String? locationName,
  }) async {
    await ensureOnline();
    return _remote.verifyTwoFactor(challengeId: challengeId, code: code, locationName: locationName);
  }

  Future<void> resetPassword({
    required String username,
    required String phoneNumber,
    required String locationName,
    required String newPassword,
  }) async {
    await ensureOnline();
    return _remote.resetPassword(
      username: username,
      phoneNumber: phoneNumber,
      locationName: locationName,
      newPassword: newPassword,
    );
  }
}

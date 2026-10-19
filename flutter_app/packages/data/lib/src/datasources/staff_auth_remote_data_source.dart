import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import 'dio_executor.dart';

/// What `POST /users/login` answered: a session, or — for an account with
/// two-factor on — a challenge that `POST /users/login/verify` turns into one.
sealed class StaffLoginOutcome {
  const StaffLoginOutcome();
}

/// Signed in: the bearer token + the resolved identity.
class StaffSignedIn extends StaffLoginOutcome {
  const StaffSignedIn({required this.token, required this.identity});
  final String token;
  final StaffIdentity identity;
}

/// Password accepted, a 6-digit code was emailed; no token yet.
class StaffTwoFactorChallenge extends StaffLoginOutcome {
  const StaffTwoFactorChallenge({
    required this.challengeId,
    this.sentTo,
    this.expiresAt,
    this.locationName,
  });

  final String challengeId;

  /// Masked address the code went to (e.g. `ra***@rvmcad.org`).
  final String? sentTo;
  final DateTime? expiresAt;

  /// Branch echoed by the backend; sent back on verify so the token carries it.
  final String? locationName;
}

/// Staff auth over the Scheduler Dio (username/password/location → JWT bearer).
class StaffAuthRemoteDataSource with DioExecutor {
  StaffAuthRemoteDataSource(this._dio);

  final Dio _dio;

  Future<StaffLoginOutcome> login({
    required String username,
    required String password,
    required String locationName,
  }) =>
      guard(() async {
        final response = await _dio.post('/users/login', data: {
          'username': username,
          'password': password,
          'locationName': locationName,
        });
        final data = asMap(response.data);
        if (data['two_factor_required'] == true) {
          final challengeId = (data['challenge_id'] ?? '').toString();
          if (challengeId.isEmpty) throw const ParseFailure();
          return StaffTwoFactorChallenge(
            challengeId: challengeId,
            sentTo: data['sent_to']?.toString(),
            expiresAt: DateTime.tryParse((data['expires_at'] ?? '').toString()),
            locationName: data['location_name']?.toString(),
          );
        }
        return _signedIn(data);
      });

  /// Second factor: the challenge + the emailed code → the same payload login
  /// returns for a non-2FA account.
  Future<StaffSignedIn> verifyTwoFactor({
    required String challengeId,
    required String code,
    String? locationName,
  }) =>
      guard(() async {
        final response = await _dio.post('/users/login/verify', data: {
          'challenge_id': challengeId,
          'code': code,
          'location_name': locationName,
        });
        return _signedIn(asMap(response.data));
      });

  /// `{token, user}` → session. A 200 without a token is a contract break, not
  /// a non-staff account — say so instead of resolving an unknown role.
  StaffSignedIn _signedIn(Map<String, dynamic> data) {
    final token = (data['token'] ?? '').toString();
    if (token.isEmpty) throw const ParseFailure();
    final user = data['user'];
    final identity = user is Map
        ? StaffIdentity.fromLoginUser(Map<String, dynamic>.from(user))
        : (StaffIdentity.fromToken(token) ?? const StaffIdentity(userId: '', role: AppRole.unknown));
    return StaffSignedIn(token: token, identity: identity);
  }

  /// Public password reset (username + phone verification). No auth required.
  Future<void> resetPassword({
    required String username,
    required String phoneNumber,
    required String locationName,
    required String newPassword,
  }) =>
      guard(() async => _dio.post('/users/reset-password', data: {
            'username': username,
            'phone_number': phoneNumber,
            'locationName': locationName,
            'new_password': newPassword,
          }));
}

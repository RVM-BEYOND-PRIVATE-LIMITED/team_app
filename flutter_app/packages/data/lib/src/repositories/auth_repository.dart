import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/auth_remote_data_source.dart';
import 'connectivity_guard.dart';

class AuthRepository with ConnectivityGuard {
  AuthRepository({required AuthRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final AuthRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  /// `true` = OTP sent; `false` = new phone, backend needs an email first.
  Future<bool> sendOtp(String phone, {String? email}) async {
    await ensureOnline();
    return _remote.sendOtp(phone, email: email);
  }

  Future<PasswordAuthResult> verifyOtp(String phone, String otp) async {
    await ensureOnline();
    return _remote.verifyOtp(phone, otp);
  }

  /// DEV-ONLY: mint a real candidate session via `/dev/bypass-login` (no OTP).
  /// Inert against a production backend (that route 404s there).
  Future<void> devBypassLogin() async {
    await ensureOnline();
    return _remote.devBypassLogin();
  }

  /// Persist the candidate profile (self-registration). Requires an OTP session.
  Future<void> register(CandidateRegistration payload) async {
    await ensureOnline();
    return _remote.register(payload);
  }

  /// Current identity, or null when there is definitively no session (the data
  /// source maps an expected 401 to null without throwing). Other failures
  /// (offline/server) propagate so the caller can react.
  Future<AuthUser?> me() async {
    await ensureOnline();
    return _remote.me();
  }

  Future<void> logout() async {
    try {
      await ensureOnline();
      await _remote.logout();
    } on Failure {
      // Logout is best-effort — the caller clears the local session regardless.
    }
  }

  // ── Password login / reset / setup ────────────────────────────────────────
  Future<PasswordAuthResult> passwordLogin({required String identifier, required String password}) async {
    await ensureOnline();
    return _remote.passwordLogin(identifier: identifier, password: password);
  }

  Future<String> resetRequestOtp(String identifier) async {
    await ensureOnline();
    return _remote.resetRequestOtp(identifier);
  }

  Future<void> resetVerifyOtp(String otp) async {
    await ensureOnline();
    return _remote.resetVerifyOtp(otp);
  }

  Future<PasswordAuthResult> resetSet({required String password, required String confirmPassword}) async {
    await ensureOnline();
    return _remote.resetSet(password: password, confirmPassword: confirmPassword);
  }

  Future<String> setupRequestOtp(String identifier) async {
    await ensureOnline();
    return _remote.setupRequestOtp(identifier);
  }

  Future<void> setupVerifyOtp(String otp) async {
    await ensureOnline();
    return _remote.setupVerifyOtp(otp);
  }

  Future<PasswordAuthResult> setupSet({required String password, required String confirmPassword}) async {
    await ensureOnline();
    return _remote.setupSet(password: password, confirmPassword: confirmPassword);
  }
}

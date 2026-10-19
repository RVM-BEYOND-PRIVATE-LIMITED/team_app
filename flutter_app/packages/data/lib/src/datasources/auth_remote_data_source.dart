import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Candidate auth over the JobPortal Dio (phone → OTP → `rvm_session` cookie).
class AuthRemoteDataSource with DioExecutor {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  /// Backend `/auth/otp/send` and `/auth/otp/verify` are discriminated on
  /// `role` and expect a bare 10-digit Indian number (regex `^[6-9]\d{9}$`,
  /// no `+91`/spaces). Normalize whatever the UI collected and tag the role,
  /// else Zod rejects the body with 400.
  /// Returns `true` when an OTP was sent, `false` when the phone is NEW and the
  /// backend needs an email first (HTTP 404). That 404 is EXPECTED (it's how a
  /// new user is detected), so it's accepted as a valid status and returned as
  /// `false` instead of throwing — which keeps this normal signup path from
  /// tripping the debugger's "pause on exception". Genuine errors (409 conflict,
  /// 5xx, offline/timeout) still throw as typed failures.
  Future<bool> sendOtp(String phone, {String? email}) => guard(() async {
        final res = await _dio.post(
          '/auth/otp/send',
          data: {
            'phone': _phone10(phone),
            'role': 'candidate',
            // A new phone (first 404) requires an email so the backend can create
            // the candidate stub; existing candidates omit it.
            if (email != null && email.isNotEmpty) 'email': email,
          },
          options: Options(validateStatus: (s) => s != null && ((s >= 200 && s < 300) || s == 404)),
        );
        return res.statusCode != 404;
      });

  /// Verify the OTP. On success the `rvm_session` cookie is set; the result's
  /// [PasswordAuthResult.needsRegistration] / [banned] tell the app where to go
  /// (registration for a new/incomplete candidate, ban flow, or home).
  Future<PasswordAuthResult> verifyOtp(String phone, String otp) => guard(() async {
        final r = await _dio.post('/auth/otp/verify',
            data: {'phone': _phone10(phone), 'otp': otp, 'role': 'candidate'});
        return Parse.passwordAuthResult(asMap(r.data));
      });

  /// Strip non-digits and any country/trunk prefix, keeping the last 10 digits:
  /// `+91 98765 43210` / `09876543210` → `9876543210`.
  static String _phone10(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  /// DEV-ONLY sign-in: backend `/dev/bypass-login` mints a real candidate
  /// `rvm_session` cookie (the cookie jar stores it) with no OTP. Returns 404
  /// in production, so this is inert in a release backend. Real session + real
  /// DB — only the login *entry* is faked. Gate the call behind a build flag.
  Future<void> devBypassLogin() =>
      guard(() async => _dio.post('/dev/bypass-login', data: {'role': 'candidate'}));

  /// Self-registration — persists the candidate profile. Requires an active
  /// candidate session (from OTP verify). Writes to the backend.
  Future<void> register(CandidateRegistration payload) =>
      guard(() async => _dio.post('/auth/registrations', data: payload.toJson()));

  /// Current identity, or `null` when there is definitively no session.
  ///
  /// A 401 here is EXPECTED and routine (the startup probe checks whether a
  /// JobPortal session exists yet — the candidate signs in via the Scheduler,
  /// so often it doesn't). We therefore accept 401 as a valid status and return
  /// null instead of letting dio throw a `DioException`. That keeps this probe
  /// from tripping the debugger's "pause on exception" and from logging a
  /// misleading error line for a perfectly normal, signed-out state. Genuine
  /// failures (offline / 5xx / timeout) still throw and are logged as errors.
  Future<AuthUser?> me() => guard(() async {
        final res = await _dio.get(
          '/auth/me',
          options: Options(validateStatus: (s) => s == 200 || s == 401),
        );
        if (res.statusCode == 401) return null;
        return Parse.authUser(asMap(res.data));
      });

  Future<void> logout() => guard(() async => _dio.delete('/auth/sessions'));

  // ── Password login (candidate) ──────────────────────────────────────────
  /// Sets the `rvm_session` cookie on success. 404 = feature off, 401 =
  /// invalid credentials. [identifier] is an email or 10-digit phone.
  Future<PasswordAuthResult> passwordLogin({required String identifier, required String password}) =>
      guard(() async => Parse.passwordAuthResult(asMap((await _dio.post('/auth/password/login',
              data: {'identifier': identifier, 'password': password, 'role': 'candidate'}))
          .data)));

  // ── Forgot password (reset) — 3 steps over a pending cookie ─────────────
  /// Returns the masked phone the OTP was sent to (enumeration-safe: always 200).
  Future<String> resetRequestOtp(String identifier) => guard(() async => asMap(
          (await _dio.post('/auth/password/reset/request-otp',
                  data: {'identifier': identifier, 'role': 'candidate'}))
              .data)['masked_phone']
      ?.toString() ??
      '');

  Future<void> resetVerifyOtp(String otp) =>
      guard(() async => _dio.post('/auth/password/reset/verify-otp', data: {'otp': otp}));

  Future<PasswordAuthResult> resetSet({required String password, required String confirmPassword}) =>
      guard(() async => Parse.passwordAuthResult(asMap((await _dio.post('/auth/password/reset/set',
              data: {'password': password, 'confirm_password': confirmPassword}))
          .data)));

  // ── First-time password setup — mirrors reset ───────────────────────────
  Future<String> setupRequestOtp(String identifier) => guard(() async => asMap(
          (await _dio.post('/auth/password/setup/request-otp',
                  data: {'identifier': identifier, 'role': 'candidate'}))
              .data)['masked_phone']
      ?.toString() ??
      '');

  Future<void> setupVerifyOtp(String otp) =>
      guard(() async => _dio.post('/auth/password/setup/verify-otp', data: {'otp': otp}));

  Future<PasswordAuthResult> setupSet({required String password, required String confirmPassword}) =>
      guard(() async => Parse.passwordAuthResult(asMap((await _dio.post('/auth/password/setup/set',
              data: {'password': password, 'confirm_password': confirmPassword}))
          .data)));
}

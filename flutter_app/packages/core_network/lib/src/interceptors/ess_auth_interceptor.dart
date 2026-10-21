import 'dart:convert';

import 'package:dio/dio.dart';

import '../ess_token_store.dart';
import '../token_store.dart';

/// Team RVM ESS client auth (task A3): attaches the bearer token and, on a
/// rejected token, silently rotates the "kept sign-in" once with the stored
/// refresh token, then replays the original request.
///
/// The ESS access token is minted in the Scheduler's own format and stored in
/// the Scheduler token slot ([TokenStore]), so [EssTokenStore] only carries the
/// refresh token and the install id. The refresh call goes through a bare
/// [refreshDio] (no interceptors), which is how a 401 on it ends the family
/// without recursion.
class EssAuthInterceptor extends Interceptor {
  EssAuthInterceptor({
    required TokenStore tokens,
    required EssTokenStore essTokens,
    required Dio refreshDio,
  })  : _tokens = tokens,
        _ess = essTokens,
        _refreshDio = refreshDio;

  final TokenStore _tokens;
  final EssTokenStore _ess;
  final Dio _refreshDio;

  static const _retriedKey = 'ess_retried';

  /// The kept-sign-in exchange. Its 401 means "this Scheduler sign-in is not
  /// fresh enough to keep" — not that the current session is over — so it must
  /// never sign the person out.
  static const _exchangePath = '/session';

  /// One in-flight rotation is shared by every request that 401s together.
  Future<bool>? _rotating;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    var token = await _tokens.readSchedulerToken();
    // Rotate BEFORE sending when the access token is spent or about to be.
    // Waiting for the server's 401 means dio throws a DioException on every
    // launch (the debugger stops on it) even though we then recover and retry.
    // Refreshing first keeps the expected-expiry path a plain 200.
    if (_isExpired(token) && await _ess.readEssRefreshToken() != null) {
      final rotated =
          await (_rotating ??= _rotate().whenComplete(() => _rotating = null));
      if (rotated) token = await _tokens.readSchedulerToken();
    }
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  /// True when the token's `exp` is missing nothing but is close enough to
  /// matter: 30 seconds of leeway covers a request that would expire in
  /// flight. A token with no readable `exp` is left to the server's answer.
  bool _isExpired(String? token) {
    final parts = token?.split('.');
    if (parts == null || parts.length != 3) return false;
    try {
      final claims = json
          .decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = claims is Map ? claims['exp'] : null;
      if (exp is! num) return false;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return expiresAt
          .isBefore(DateTime.now().add(const Duration(seconds: 30)));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final isRejected = err.response?.statusCode == 401;
    if (!isRejected || options.extra[_retriedKey] == true) {
      // A 401 that could not be rotated (or survived the rotation) ends the
      // session: sign out here so the app returns to login instead of leaving
      // every screen on a raw "bad response" error.
      if (isRejected) await _endSession(options);
      handler.next(err);
      return;
    }
    if (await _ess.readEssRefreshToken() == null) {
      await _endSession(options);
      handler.next(err);
      return;
    }

    final rotated =
        await (_rotating ??= _rotate().whenComplete(() => _rotating = null));
    if (!rotated) {
      await _endSession(options);
      handler.next(err);
      return;
    }

    try {
      final token = await _tokens.readSchedulerToken();
      final retried = options
        ..extra[_retriedKey] = true
        ..headers['Authorization'] = 'Bearer $token';
      final response = await _refreshDio.fetch(retried);
      handler.resolve(response);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) await _endSession(options);
      handler.next(e);
    }
  }

  /// The ESS refused this token and no rotation can rescue it. Drop both halves
  /// of the session so the app returns to login, not to a screen that keeps
  /// drawing 401s. The kept-sign-in exchange is exempt: its 401 only says the
  /// Scheduler sign-in is too old to keep, and the session itself is fine.
  Future<void> _endSession(RequestOptions options) async {
    if (options.path == _exchangePath) return;
    await _ess.clearEssSession();
    await _tokens.onUnauthorized();
  }

  Future<bool> _rotate() async {
    final refreshToken = await _ess.readEssRefreshToken();
    if (refreshToken == null) return false;
    final installId = await _ess.installId();
    try {
      final res = await _refreshDio.post<Map<String, dynamic>>(
        '/session/refresh',
        data: {'refresh_token': refreshToken, 'install_id': installId},
      );
      final data = res.data;
      final access = data?['access_token'];
      final refresh = data?['refresh_token'];
      if (access is! String || refresh is! String) {
        await _ess.clearEssSession();
        return false;
      }
      await _ess.saveEssSession(
        accessToken: access,
        refreshToken: refresh,
        accessExpiresAt: DateTime.tryParse('${data?['access_expires_at']}'),
      );
      return true;
    } on DioException catch (e) {
      // Only a refusal ends the family (expired, signed out, reused, password
      // changed…). A timeout or a 5xx is the network/server having a bad
      // moment; keep the refresh token so the next attempt can still restore.
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) await _ess.clearEssSession();
      return false;
    }
  }
}

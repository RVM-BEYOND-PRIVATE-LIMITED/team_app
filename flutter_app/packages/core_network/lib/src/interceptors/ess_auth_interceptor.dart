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

  /// One in-flight rotation is shared by every request that 401s together.
  Future<bool>? _rotating;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokens.readSchedulerToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final isRejected = err.response?.statusCode == 401;
    if (!isRejected || options.extra[_retriedKey] == true || await _ess.readEssRefreshToken() == null) {
      handler.next(err);
      return;
    }

    final rotated = await (_rotating ??= _rotate().whenComplete(() => _rotating = null));
    if (!rotated) {
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
      handler.next(e);
    }
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
    } on DioException {
      // The family is over (expired, signed out, reused, password changed…).
      await _ess.clearEssSession();
      return false;
    }
  }
}

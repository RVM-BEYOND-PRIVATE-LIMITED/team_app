import 'dart:convert';

import 'package:dio/dio.dart';

import '../token_store.dart';

/// Attaches the Scheduler bearer token to every request and triggers
/// [TokenStore.onUnauthorized] when the Scheduler REJECTS THE TOKEN. The
/// Scheduler JWT is a 64h access token with NO refresh endpoint, so a rejected
/// token == session over == sign out.
///
/// Not every Scheduler 401 is a rejected token: several controllers answer 401
/// for their own reasons while the session is fine (e.g. GET /activities →
/// "Authentication required with location."). Signing out on those kicks a
/// working user back to login, so only a real rejection ends the session.
class BearerAuthInterceptor extends Interceptor {
  BearerAuthInterceptor(this._tokens, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final TokenStore _tokens;
  final DateTime Function() _now;

  /// The only bodies the Scheduler's auth guards send when they reject a token
  /// (middleware/auth.js, allowRoles.js, requireRole.js).
  static const _tokenRejections = {'No token provided', 'Please authenticate'};

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
    if (err.response?.statusCode == 401 && await _isSessionOver(err.response?.data)) {
      await _tokens.onUnauthorized();
    }
    handler.next(err);
  }

  /// Session over when the stored JWT has expired, the auth guard rejected the
  /// token, or the 401 carries no Scheduler error text to tell otherwise.
  Future<bool> _isSessionOver(dynamic body) async {
    if (_isExpired(await _tokens.readSchedulerToken())) return true;
    final error = body is Map ? body['error'] : null;
    if (error is! String) return true;
    return _tokenRejections.contains(error);
  }

  /// True only when the token's `exp` claim is in the past. Unreadable tokens
  /// are left to the server's answer.
  bool _isExpired(String? token) {
    final parts = token?.split('.');
    if (parts == null || parts.length != 3) return false;
    try {
      final claims = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = claims is Map ? claims['exp'] : null;
      if (exp is! num) return false;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000).isBefore(_now());
    } catch (_) {
      return false;
    }
  }
}

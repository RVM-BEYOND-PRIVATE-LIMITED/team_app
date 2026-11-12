import 'package:dio/dio.dart';

import '../session_rotator.dart';
import '../token_store.dart';

/// Attaches the Scheduler bearer token to every request and decides, from the
/// reply's `code`, whether a 401 ends the session.
///
/// With [sessions] (the kept sign-in shared with the ESS client, team_app #50)
/// the token is also renewed: before sending when it is about to expire, and
/// once after the Scheduler refuses it, after which the request is sent again
/// through [dio]. That keeps a Scheduler-only screen working past the access
/// token's hour, for a portal and for an attendance-only sign-in.
///
/// Not every Scheduler 401 is a rejected token: several controllers answer 401
/// for their own reasons while the session is fine (e.g. GET /activities →
/// "Authentication required with location."). Signing out on those kicks a
/// working user back to login, so [SessionRotator.verdictFor] decides.
class BearerAuthInterceptor extends Interceptor {
  BearerAuthInterceptor(
    this._tokens, {
    DateTime Function()? clock,
    SessionRotator? sessions,
    Dio? dio,
  })  : _now = clock ?? sessions?.clock ?? DateTime.now,
        _sessions = sessions,
        _dio = dio;

  final TokenStore _tokens;
  final DateTime Function() _now;
  final SessionRotator? _sessions;
  final Dio? _dio;

  static const _retriedKey = 'rvm.auth.retried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final sessions = _sessions;
    final token = sessions == null
        ? await _tokens.readSchedulerToken()
        : await sessions.tokenForRequest();
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
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }
    final options = err.requestOptions;
    final verdict = SessionRotator.verdictFor(
      err.response?.data,
      sentToken: _sentToken(options) ?? await _tokens.readSchedulerToken(),
      now: _now(),
    );
    if (verdict == SessionVerdict.keep) {
      handler.next(err);
      return;
    }

    // Renew once, then send the request again. Without a kept sign-in, after
    // a renewal that did not succeed, or when the renewed token is refused
    // too, the session is over, unless the verdict says to keep it.
    final sessions = _sessions;
    final dio = _dio;
    if (verdict == SessionVerdict.over ||
        sessions == null ||
        dio == null ||
        options.extra[_retriedKey] == true ||
        !await sessions.renew()) {
      if (verdict != SessionVerdict.renewOrKeep) await _endSession();
      handler.next(err);
      return;
    }

    options.extra[_retriedKey] = true;
    try {
      // The replay runs the whole chain again, so it picks up the renewed
      // token, the punch cookie and the same Idempotency-Key, and a 401 on it
      // is judged here once more, with no second renewal.
      handler.resolve(await dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<void> _endSession() async {
    final sessions = _sessions;
    if (sessions != null) {
      await sessions.endSession();
    } else {
      await _tokens.onUnauthorized();
    }
  }

  /// The token the refused request carried.
  static String? _sentToken(RequestOptions options) {
    final header = options.headers['Authorization'];
    if (header is! String || !header.startsWith('Bearer ')) return null;
    final token = header.substring('Bearer '.length);
    return token.isEmpty ? null : token;
  }
}

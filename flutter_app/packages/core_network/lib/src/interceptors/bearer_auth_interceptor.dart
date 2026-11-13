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
///
/// When the person's access has ended (an exited account, a changed password,
/// an employee record no longer active: [SessionRotator.accessEndedCodes]),
/// the session ends with the server's message for the sign-in screen
/// (team_app #52 item 8). A 403 `NOT_ACTIVE` ends it too, the one 403 that
/// does, whether the client throws it or returns it as a reply.
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

  /// A client that takes refusals as replies (the app's accepts every status
  /// but 401) hands a 403 here rather than to [onError].
  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    await _endIfAccessEnded(response);
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401) {
      await _endIfAccessEnded(err.response);
      handler.next(err);
      return;
    }
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
        options.extra[_retriedKey] == true) {
      await _refused(err, handler, verdict);
      return;
    }
    if (!await sessions.renew()) {
      await _refused(err, handler, verdict,
          refusal: sessions.refusalMessage);
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

  /// The 401 stands: the session is over unless [verdict] keeps it. Its
  /// message for the sign-in screen is the reply's own when access has ended,
  /// else the refused renewal's ([refusal]).
  Future<void> _refused(
    DioException err,
    ErrorInterceptorHandler handler,
    SessionVerdict verdict, {
    String? refusal,
  }) async {
    if (verdict != SessionVerdict.renewOrKeep) {
      await _endSession(
          message:
              SessionRotator.accessEndedMessage(err.response?.data) ?? refusal);
    }
    handler.next(err);
  }

  /// A 403 `NOT_ACTIVE` ([SessionRotator.endsSessionOn403]) to a request
  /// that carried a token ends the session with the server's message. A
  /// refused sign-in (no token yet) is the sign-in screen's to show.
  Future<void> _endIfAccessEnded(Response<dynamic>? response) async {
    if (response == null ||
        response.statusCode != 403 ||
        !SessionRotator.endsSessionOn403(response.data) ||
        _sentToken(response.requestOptions) == null) {
      return;
    }
    await _endSession(message: SessionRotator.accessEndedMessage(response.data));
  }

  Future<void> _endSession({String? message}) async {
    final sessions = _sessions;
    if (sessions != null) {
      await sessions.endSession(message: message);
    } else {
      await _tokens.onUnauthorized(message: message);
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

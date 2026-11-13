import 'package:dio/dio.dart';

import '../ess_token_store.dart';
import '../session_rotator.dart';
import '../token_store.dart';

/// Team RVM ESS client auth (task A3): attaches the bearer token and, on a
/// rejected token, silently rotates the "kept sign-in" once with the stored
/// refresh token, then replays the original request.
///
/// The ESS access token is minted in the Scheduler's own format and stored in
/// the Scheduler token slot ([TokenStore]), so [EssTokenStore] only carries the
/// refresh token and the install id. The rotation itself is the
/// [SessionRotator] the Scheduler client shares (team_app #50), so both clients
/// renew in one flight. The replay goes through a bare [refreshDio] (no
/// interceptors), which is how a 401 on it ends the family without recursion.
///
/// A refresh refused because the person left or changed their password ends
/// the session with the ESS's message for the sign-in screen (team_app #52
/// item 8, [SessionRotator.accessEndedMessage]). A 403 never ends it: a 403
/// `NOT_ACTIVE` reaches the screen that asked, as before.
class EssAuthInterceptor extends Interceptor {
  EssAuthInterceptor({
    required TokenStore tokens,
    required EssTokenStore essTokens,
    required Dio refreshDio,
    SessionRotator? sessions,
  })  : _tokens = tokens,
        _refreshDio = refreshDio,
        _sessions = sessions ??
            SessionRotator(
              tokens: tokens,
              essTokens: essTokens,
              refreshDio: refreshDio,
            );

  final TokenStore _tokens;
  final Dio _refreshDio;
  final SessionRotator _sessions;

  static const _retriedKey = 'ess_retried';

  /// The kept-sign-in exchange. Its 401 means "this Scheduler sign-in is not
  /// fresh enough to keep" — not that the current session is over — so it must
  /// never sign the person out.
  static const _exchangePath = '/session';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Rotates BEFORE sending when the access token is spent or about to be.
    final token = await _sessions.tokenForRequest();
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
    // Only a 401 about the TOKEN ends a session. The ESS's account surface
    // answers 401 WRONG_PASSWORD for a bad current password (issue #13) and
    // that must reach the screen as a message, not sign the person out.
    final tokenRejected = _isTokenRejection(err);
    if (!tokenRejected || options.extra[_retriedKey] == true) {
      // A token rejection that could not be rotated (or survived the rotation)
      // ends the session: sign out here so the app returns to login instead of
      // leaving every screen on a raw "bad response" error.
      if (tokenRejected) await _endSession(options);
      handler.next(err);
      return;
    }

    // No kept sign-in, or a rotation that did not succeed, ends the session.
    // A refresh refused because the person left or changed their password
    // says so, and the sign-in screen shows it.
    if (!await _sessions.renew()) {
      await _endSession(options, message: _sessions.refusalMessage);
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

  /// True when a 401 is about the token itself. The ESS marks those
  /// `NOT_AUTHENTICATED`; any other 401 (`WRONG_PASSWORD` on `/me/password`)
  /// is a refusal of what the request said and belongs on the screen.
  /// A 401 with no readable body keeps the old behaviour (treated as a token).
  bool _isTokenRejection(DioException err) {
    if (err.response?.statusCode != 401) return false;
    final data = err.response?.data;
    if (data is Map) {
      final code = data['code']?.toString();
      if (code != null && code.isNotEmpty) return code == 'NOT_AUTHENTICATED';
      final error = data['error']?.toString();
      if (error != null && error.isNotEmpty) {
        return error == 'Please authenticate' || error == 'No token provided';
      }
    }
    return true;
  }

  /// The ESS refused this token and no rotation can rescue it. Drop both halves
  /// of the session so the app returns to login, not to a screen that keeps
  /// drawing 401s. The kept-sign-in exchange is exempt: its 401 only says the
  /// Scheduler sign-in is too old to keep, and the session itself is fine.
  Future<void> _endSession(RequestOptions options, {String? message}) async {
    if (options.path == _exchangePath) return;
    await _sessions.endSession(message: message);
  }
}

import 'dart:convert';

import 'package:dio/dio.dart';

import 'ess_token_store.dart';
import 'token_store.dart';

/// What a 401 reply means for the session.
enum SessionVerdict {
  /// A refusal of what the request said (a wrong password), not of the
  /// session. The reply reaches the screen and nobody is signed out.
  keep,

  /// The access token itself was refused: renew it once and send the request
  /// again. If that does not help, the session is over.
  renew,

  /// Renew once and send again, as [renew], but if that does not help the
  /// session is kept. Only the punch path reads an attendance token; every
  /// other Scheduler route answers it `INVALID_TOKEN`. That is a path this
  /// sign-in cannot use, which renewal cannot fix, not a spent session.
  renewOrKeep,

  /// The session is over and renewal cannot help: sign the person out.
  over,
}

/// The kept sign-in's renewal (task A3), shared by every client that sends the
/// access token (team_app #50 item 3).
///
/// The Team RVM backend (ESS) mints the one-hour access token in the
/// Scheduler's own format, and it is stored in the Scheduler token slot, so one
/// token serves both hosts and one refresh renews it for both. The ESS client
/// and the Scheduler client hold the SAME rotator: renewals that overlap are
/// one `POST /session/refresh`, never two with the same refresh token.
///
/// The refresh goes through a bare [Dio] with no interceptors, so a refused
/// refresh cannot recurse into another renewal.
class SessionRotator {
  SessionRotator({
    required TokenStore tokens,
    required EssTokenStore essTokens,
    required Dio refreshDio,
    DateTime Function()? clock,
  })  : _tokens = tokens,
        _ess = essTokens,
        _refreshDio = refreshDio,
        clock = clock ?? DateTime.now;

  final TokenStore _tokens;
  final EssTokenStore _ess;
  final Dio _refreshDio;

  /// The time the expiry checks use. Tests pass a fake clock.
  final DateTime Function() clock;

  /// A token this close to its `exp` is renewed before it is sent, so it
  /// cannot expire in flight.
  static const leeway = Duration(seconds: 30);

  /// 401 codes after which no renewal can help (Scheduler_Backend main,
  /// middleware/auth.js): no token sent, no such account, an exited account,
  /// a password changed since the sign-in.
  static const sessionOverCodes = {
    'NO_TOKEN',
    'USER_NOT_FOUND',
    'ACCOUNT_EXITED',
    'PASSWORD_CHANGED',
  };

  /// 401 codes that refuse the access token itself, so a renewed one may pass:
  /// `TOKEN_EXPIRED` and `INVALID_TOKEN` (Scheduler middleware/auth.js), and
  /// `NOT_AUTHENTICATED` (the ESS's token code in lib/errors.js, which the
  /// Scheduler's punch path also sends for an attendance sign-in).
  static const renewableCodes = {
    'TOKEN_EXPIRED',
    'INVALID_TOKEN',
    'NOT_AUTHENTICATED',
  };

  /// The bodies the Scheduler's older guards (allowRoles.js, requireRole.js,
  /// staffOnly.js) send with no `code` when they refuse a token.
  static const _codelessRejections = {'No token provided', 'Please authenticate'};

  /// Codes that say the person's access has ended, not only this token's
  /// (team_app #52 item 8). The reply's message is shown on the sign-in
  /// screen:
  ///  * 401 `ACCOUNT_EXITED` and 401 `PASSWORD_CHANGED`: the Scheduler's
  ///    middleware/auth.js, for an exited account and for a token issued
  ///    before the password last changed;
  ///  * 403 `NOT_ACTIVE`: an employee record that is no longer active, from
  ///    the Scheduler's punch path (controllers/hr/attendancePunchController.js
  ///    loadEmployee) and from every ESS route (apps/ess-api
  ///    src/middleware/employeeAuth.js).
  static const accessEndedCodes = {
    'ACCOUNT_EXITED',
    'PASSWORD_CHANGED',
    'NOT_ACTIVE',
  };

  /// The ESS's reasons for refusing a refresh that mean the same: the
  /// employee has left, or the password changed since the sign-in (apps/ess-api
  /// src/routes/sessions.js, the `reason` of a 401 from `/session/refresh`).
  static const accessEndedReasons = {'left', 'password_changed'};

  /// One in-flight renewal is shared by everybody who asks while it runs.
  Future<bool>? _rotating;

  /// Why the last renewal was refused, when the ESS said access has ended.
  ///
  /// It outlives the refused refresh. A renewal before sending
  /// ([tokenForRequest]) still sends the old token, and the 401 that token
  /// draws asks for a renewal again, which now has no refresh token to send.
  /// That 401 is the one that ends the session, so the reason must still be
  /// here then. It goes when a refresh is sent again, when the session ends,
  /// and when the access token is no longer [_refusedToken] (somebody signed
  /// in again), so it never reaches a later sign-in.
  String? _refusal;

  /// The access token in use when the refresh was refused.
  String? _refusedToken;

  /// The access token to send. When it is about to expire and a kept sign-in
  /// can renew it, it is renewed first: waiting for the server's 401 would
  /// throw a DioException (the debugger stops on it) even though the request
  /// then recovers.
  Future<String?> tokenForRequest() async {
    final token = await _tokens.readSchedulerToken();
    if (!isExpiring(token) || await _ess.readEssRefreshToken() == null) {
      return token;
    }
    return await renew() ? await _tokens.readSchedulerToken() : token;
  }

  /// Renews the kept sign-in. True when a fresh access token is stored.
  Future<bool> renew() =>
      _rotating ??= _rotate().whenComplete(() => _rotating = null);

  /// The server's message when a renewal of this sign-in was refused because
  /// the person's access has ended ([accessEndedReasons]), else null. Read it
  /// right after a [renew] that answered false: it stays until the session
  /// ends, including through a renewal that had no refresh token left to
  /// send.
  String? get refusalMessage => _refusal;

  /// Ends both halves of the session, the kept sign-in and the access token,
  /// so the app returns to sign-in instead of a screen that keeps drawing 401s.
  /// [message] is the server's reason when access has ended, for the sign-in
  /// screen ([accessEndedMessage]).
  Future<void> endSession({String? message}) async {
    _clearRefusal();
    await _ess.clearEssSession();
    await _tokens.onUnauthorized(message: message);
  }

  /// The server's own message when [body] says the person's access has ended
  /// ([accessEndedCodes], or a refused refresh's [accessEndedReasons]), else
  /// null. Every other refusal keeps today's silent return to sign-in.
  static String? accessEndedMessage(Object? body) {
    if (body is! Map) return null;
    if (!accessEndedCodes.contains(body['code']) &&
        !accessEndedReasons.contains(body['reason'])) {
      return null;
    }
    final error = body['error'];
    final text = error is String ? error.trim() : '';
    return text.isEmpty ? null : text;
  }

  /// True for a 403 that ends the session: `NOT_ACTIVE`, the employee record
  /// is no longer active, so nothing this sign-in asks for will be answered.
  /// Every other 403 refuses one request and keeps the session.
  static bool endsSessionOn403(Object? body) =>
      body is Map && body['code'] == 'NOT_ACTIVE';

  /// True when [token] expires within [leeway] of now. A token with no
  /// readable `exp` is left to the server's answer.
  bool isExpiring(String? token) {
    final expiresAt = expiryOf(token);
    return expiresAt != null && expiresAt.isBefore(clock().add(leeway));
  }

  /// What a 401 means for the session. The reply's `code` decides:
  ///  * [sessionOverCodes]: [SessionVerdict.over].
  ///  * [renewableCodes]: [SessionVerdict.renew], except `INVALID_TOKEN` for
  ///    an attendance token that has not expired: [SessionVerdict.renewOrKeep].
  ///    The punch path answers an attendance token that HAS expired with
  ///    `INVALID_TOKEN` too, and a phone clock running behind can make it look
  ///    live, so renewal is still tried first.
  ///  * any other code: [SessionVerdict.keep].
  ///
  /// A 401 with no code (an older guard, a proxy page) keeps the rules the
  /// Scheduler client always had: a token past its `exp` is renewed, a
  /// missing body or a token rejection ends the session, anything else is
  /// kept. [sentToken] is the token the refused request carried.
  static SessionVerdict verdictFor(
    Object? body, {
    required String? sentToken,
    required DateTime now,
  }) {
    final code = body is Map ? body['code'] : null;
    if (code is String && code.isNotEmpty) {
      if (sessionOverCodes.contains(code)) return SessionVerdict.over;
      if (!renewableCodes.contains(code)) return SessionVerdict.keep;
      if (code == 'INVALID_TOKEN' &&
          isAttendanceToken(sentToken) &&
          !_isExpired(sentToken, now)) {
        return SessionVerdict.renewOrKeep;
      }
      return SessionVerdict.renew;
    }
    if (_isExpired(sentToken, now)) return SessionVerdict.renew;
    final error = body is Map ? body['error'] : null;
    if (error is! String) return SessionVerdict.over;
    return _codelessRejections.contains(error)
        ? SessionVerdict.over
        : SessionVerdict.keep;
  }

  /// True for an attendance-only sign-in's token (`k: 'punch'`, as both the
  /// Scheduler's issuePunchSession and the ESS's mintAttendanceToken sign it).
  static bool isAttendanceToken(String? token) => _claims(token)?['k'] == 'punch';

  /// The token's `exp`, or null when it has none the app can read.
  static DateTime? expiryOf(String? token) {
    final exp = _claims(token)?['exp'];
    return exp is num
        ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true)
        : null;
  }

  static bool _isExpired(String? token, DateTime now) =>
      expiryOf(token)?.isBefore(now) ?? false;

  /// The JWT's claims, read without checking the signature: the server checks
  /// that. Null for anything that is not a readable JWT.
  static Map<Object?, Object?>? _claims(String? token) {
    final parts = token?.split('.');
    if (parts == null || parts.length != 3) return null;
    try {
      final claims = json.decode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return claims is Map ? claims : null;
    } catch (_) {
      return null;
    }
  }

  void _clearRefusal() {
    _refusal = null;
    _refusedToken = null;
  }

  Future<bool> _rotate() async {
    final refreshToken = await _ess.readEssRefreshToken();
    if (refreshToken == null) {
      // Nothing to send. A refusal of this same sign-in still stands: the 401
      // this renewal answers ends the session, and shows the reason.
      if (_refusal != null &&
          await _tokens.readSchedulerToken() != _refusedToken) {
        _clearRefusal();
      }
      return false;
    }
    _clearRefusal();
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
      if (status == 401 || status == 403) {
        final refusal = accessEndedMessage(e.response?.data);
        if (refusal != null) {
          _refusal = refusal;
          _refusedToken = await _tokens.readSchedulerToken();
        }
        await _ess.clearEssSession();
      }
      return false;
    }
  }
}

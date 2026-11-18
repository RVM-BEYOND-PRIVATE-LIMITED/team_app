import 'dart:convert';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// The sign-in time every test starts from; its access token lasts an hour.
final _t0 = DateTime.utc(2026, 11, 12, 9);
const _employee = '00000000-0000-4000-8000-0000000000e1';

const _env = ApiEnvironment(
  schedulerBaseUrl: 'https://scheduler.test/api',
  jobPortalBaseUrl: 'https://jobs.test/api/v1',
  essBaseUrl: 'https://ess.test/api/ess',
);

String _portalToken(DateTime exp) => fakeJwt({
      'userId': 'u-test',
      'role': 'faculty',
      'iat': epochSeconds(_t0),
      'exp': epochSeconds(exp),
    });

String _attendanceToken(DateTime exp) => fakeJwt({
      'k': 'punch',
      'e': _employee,
      'm': 'pw',
      'iat': epochSeconds(_t0),
      'exp': epochSeconds(exp),
    });

Map<String, dynamic> _claims(String token) => json.decode(utf8.decode(
    base64Url.decode(base64Url.normalize(token.split('.')[1])))) as Map<String, dynamic>;

enum _Kind { portal, attendance }

/// Both hosts, faked by the rules their code applies on main:
///  * the ESS refresh (apps/ess-api src/routes/sessions.js) answers the live
///    refresh token with the next one and an access token of the same kind
///    that lasts an hour (lib/accessTokens.js), or 401 NOT_AUTHENTICATED;
///  * the Scheduler (middleware/auth.js, middleware/punchAuth.js) answers a
///    portal token past its exp 401 TOKEN_EXPIRED, and an attendance token 401
///    INVALID_TOKEN anywhere but /hr/my-attendance*, or once it has expired.
///
/// The app's clock and the servers' clock are separate, so a phone clock that
/// runs behind can be tested.
class _Hosts {
  _Hosts(this.kind, {required DateTime now, bool keptSignIn = true})
      : appNow = now,
        serverNow = now {
    final token =
        kind == _Kind.portal ? _portalToken(_t0.add(_hour)) : _attendanceToken(_t0.add(_hour));
    tokens = FakeTokens(
        schedulerToken: token, refreshToken: keptSignIn ? 'refresh-0' : null);
    _liveRefresh = tokens.refreshToken;
    sessions = SessionRotator(
      tokens: tokens,
      essTokens: tokens,
      refreshDio: Dio(BaseOptions(baseUrl: _env.essBaseUrl))
        ..httpClientAdapter = refresh,
      clock: () => appNow,
    );
    scheduler = DioFactory.scheduler(env: _env, tokens: tokens, sessions: sessions)
      ..httpClientAdapter = schedulerHost
      // As the app sets it (rvm_team_app lib/injection.dart).
      ..options.validateStatus = (s) => s != null && s != 401;
  }

  static const _hour = Duration(hours: 1);

  final _Kind kind;
  DateTime appNow;
  DateTime serverNow;
  late final FakeTokens tokens;
  late final SessionRotator sessions;
  late final Dio scheduler;
  String? _liveRefresh;
  int _minted = 0;

  /// Set to refuse the next refreshes with this reason (401).
  String? refuseRefresh;

  /// Answers the Scheduler gives instead of its auth rules, in order.
  final List<Map<String, Object?>> forced401s = [];

  int get refreshes => refresh.seen.length;

  void moveTo(DateTime at) => appNow = serverNow = at;

  late final ScriptedAdapter refresh = ScriptedAdapter((options) {
    final body = options.data as Map;
    if (refuseRefresh != null || body['refresh_token'] != _liveRefresh) {
      _liveRefresh = null;
      return jsonReply(401, {
        'error': 'Please sign in again.',
        'code': 'NOT_AUTHENTICATED',
        'reason': refuseRefresh ?? 'unknown',
      });
    }
    _liveRefresh = 'refresh-${++_minted}';
    final exp = serverNow.add(_hour);
    return jsonReply(200, {
      'access_token':
          kind == _Kind.portal ? _portalToken(exp) : _attendanceToken(exp),
      'access_expires_at': exp.toIso8601String(),
      'refresh_token': _liveRefresh,
    });
  });

  late final ScriptedAdapter schedulerHost = ScriptedAdapter((options) {
    if (forced401s.isNotEmpty) return jsonReply(401, forced401s.removeAt(0));
    final header = options.headers['Authorization'] as String?;
    if (header == null) {
      return jsonReply(401, {'error': 'No token provided', 'code': 'NO_TOKEN'});
    }
    final claims = _claims(header.substring('Bearer '.length));
    final live = DateTime.fromMillisecondsSinceEpoch((claims['exp'] as int) * 1000)
        .isAfter(serverNow);
    if (claims['k'] == 'punch') {
      if (live && options.path.startsWith('/hr/my-attendance')) {
        return jsonReply(200, {'ok': true});
      }
      return jsonReply(401, {'error': 'Please authenticate', 'code': 'INVALID_TOKEN'});
    }
    if (!live) {
      return jsonReply(401, {
        'error': 'Your session has expired. Please sign in again.',
        'code': 'TOKEN_EXPIRED',
      });
    }
    return jsonReply(200, {'ok': true});
  });
}

void main() {
  group('check 4: a Scheduler-only screen keeps working past one hour', () {
    for (final kind in _Kind.values) {
      test('${kind.name} sign-in: the token is renewed before it is sent',
          () async {
        final hosts = _Hosts(kind, now: _t0);
        for (final minutes in [61, 125, 189]) {
          hosts.moveTo(_t0.add(Duration(minutes: minutes)));
          final res = await hosts.scheduler.get<dynamic>('/hr/my-attendance/leave');
          expect(res.statusCode, 200, reason: 'at +$minutes min');
        }
        expect(hosts.tokens.unauthorized, 0, reason: 'never signed out');
        expect(hosts.refreshes, 3, reason: 'one renewal per hour');
        expect(hosts.schedulerHost.seen, hasLength(3), reason: 'no 401 at all');
      });
    }

    test('portal sign-in, phone clock behind: one renewal after the 401',
        () async {
      final hosts = _Hosts(_Kind.portal, now: _t0)
        ..appNow = _t0.add(const Duration(minutes: 10))
        ..serverNow = _t0.add(const Duration(minutes: 61));

      final res = await hosts.scheduler.post<dynamic>('/hr/my-attendance/leave',
          data: {'day': '2026-11-20'});

      expect(res.statusCode, 200);
      expect(hosts.tokens.unauthorized, 0);
      expect(hosts.refreshes, 1);
      final [first, replay] = hosts.schedulerHost.seen;
      expect(replay.bearer, isNot(first.bearer), reason: 'renewed token');
      expect(replay.idempotencyKey, first.idempotencyKey,
          reason: 'the replay is the same action');
    });

    test('attendance sign-in, phone clock behind: INVALID_TOKEN on the punch '
        'path is renewed too', () async {
      final hosts = _Hosts(_Kind.attendance, now: _t0)
        ..appNow = _t0.add(const Duration(minutes: 10))
        ..serverNow = _t0.add(const Duration(minutes: 61));

      final res = await hosts.scheduler.get<dynamic>('/hr/my-attendance');

      expect(res.statusCode, 200);
      expect(hosts.tokens.unauthorized, 0);
      expect(hosts.refreshes, 1);
      expect(hosts.schedulerHost.seen, hasLength(2));
    });
  });

  group('attendance-only sign-in on a portal-only path', () {
    test('is refused but never signed out', () async {
      final hosts = _Hosts(_Kind.attendance, now: _t0.add(const Duration(minutes: 5)));

      await expectLater(hosts.scheduler.get<dynamic>('/announcements'),
          throwsA(isA<DioException>()));

      expect(hosts.tokens.unauthorized, 0);
      expect(hosts.tokens.refreshToken, isNotNull, reason: 'kept sign-in kept');
      expect(hosts.refreshes, 1, reason: 'one renewal, then it gives up');
      expect(hosts.schedulerHost.seen, hasLength(2), reason: 'one replay only');
    });

    test('is kept without a kept sign-in too', () async {
      final hosts = _Hosts(_Kind.attendance,
          now: _t0.add(const Duration(minutes: 5)), keptSignIn: false);

      await expectLater(hosts.scheduler.get<dynamic>('/announcements'),
          throwsA(isA<DioException>()));

      expect(hosts.tokens.unauthorized, 0);
      expect(hosts.refreshes, 0);
    });

    test('an expired attendance token with nothing to renew it ends the '
        'session', () async {
      final hosts = _Hosts(_Kind.attendance,
          now: _t0.add(const Duration(minutes: 61)), keptSignIn: false);

      await expectLater(hosts.scheduler.get<dynamic>('/hr/my-attendance'),
          throwsA(isA<DioException>()));

      expect(hosts.tokens.unauthorized, 1);
    });
  });

  group('the reply code decides when a session is over', () {
    for (final code in SessionRotator.sessionOverCodes) {
      test('$code signs out at once, with no renewal', () async {
        final hosts = _Hosts(_Kind.portal, now: _t0.add(const Duration(minutes: 5)))
          ..forced401s.add({'error': 'Please sign in again.', 'code': code});

        await expectLater(hosts.scheduler.get<dynamic>('/me'),
            throwsA(isA<DioException>()));

        expect(hosts.tokens.unauthorized, 1);
        expect(hosts.tokens.refreshToken, isNull,
            reason: 'both halves of the session end');
        expect(hosts.refreshes, 0);
      });
    }

    test('a refused renewal ends the session', () async {
      final hosts = _Hosts(_Kind.portal, now: _t0.add(const Duration(minutes: 61)))
        ..refuseRefresh = 'signed_out';

      await expectLater(hosts.scheduler.get<dynamic>('/me'),
          throwsA(isA<DioException>()));

      expect(hosts.tokens.unauthorized, 1);
      expect(hosts.tokens.refreshToken, isNull);
    });

    test('with no kept sign-in an expired token ends the session as before',
        () async {
      final hosts = _Hosts(_Kind.portal,
          now: _t0.add(const Duration(minutes: 61)), keptSignIn: false);

      await expectLater(hosts.scheduler.get<dynamic>('/me'),
          throwsA(isA<DioException>()));

      expect(hosts.tokens.unauthorized, 1);
      expect(hosts.refreshes, 0);
    });

    test('a renewed token refused again ends the session, with no loop',
        () async {
      final hosts = _Hosts(_Kind.portal, now: _t0.add(const Duration(minutes: 5)))
        ..forced401s.addAll([
          {'error': 'Your session has expired.', 'code': 'TOKEN_EXPIRED'},
          {'error': 'Please authenticate', 'code': 'INVALID_TOKEN'},
        ]);

      await expectLater(hosts.scheduler.get<dynamic>('/me'),
          throwsA(isA<DioException>()));

      expect(hosts.refreshes, 1);
      expect(hosts.schedulerHost.seen, hasLength(2));
      expect(hosts.tokens.unauthorized, 1);
    });

    for (final body in [
      {'error': 'Wrong password.', 'code': 'WRONG_PASSWORD'},
      {'error': 'Authentication required with location.'},
    ]) {
      test('${body['code'] ?? body['error']} reaches the screen, session kept',
          () async {
        final hosts = _Hosts(_Kind.portal, now: _t0.add(const Duration(minutes: 5)))
          ..forced401s.add(body);

        await expectLater(hosts.scheduler.get<dynamic>('/me'),
            throwsA(isA<DioException>()));

        expect(hosts.tokens.unauthorized, 0);
        expect(hosts.refreshes, 0);
        expect(hosts.schedulerHost.seen, hasLength(1));
      });
    }
  });

  test('the Scheduler and ESS clients renew in one flight', () async {
    final hosts = _Hosts(_Kind.portal,
        now: _t0.add(const Duration(minutes: 59, seconds: 50)));
    final essApi = ScriptedAdapter((_) => jsonReply(200, {'ok': true}));
    final ess = DioFactory.ess(
      env: _env,
      tokens: hosts.tokens,
      essTokens: hosts.tokens,
      sessions: hosts.sessions,
    )..httpClientAdapter = essApi;
    final before = hosts.tokens.schedulerToken;

    await Future.wait([
      hosts.scheduler.get<dynamic>('/hr/my-attendance'),
      hosts.scheduler.get<dynamic>('/hr/my-attendance/leave'),
      ess.get<dynamic>('/me/capabilities'),
    ]);

    expect(hosts.refreshes, 1, reason: 'one refresh for both clients');
    final sent = [...hosts.schedulerHost.seen, ...essApi.seen].map((r) => r.bearer);
    expect(sent, everyElement(hosts.tokens.schedulerToken));
    expect(hosts.tokens.schedulerToken, isNot(before));
  });

  group('SessionRotator', () {
    test('a live token is sent as it is', () async {
      final hosts = _Hosts(_Kind.portal, now: _t0.add(const Duration(minutes: 20)));
      final token = hosts.tokens.schedulerToken;

      expect(await hosts.sessions.tokenForRequest(), token);
      expect(hosts.refreshes, 0);
    });

    test('an expiring token with no kept sign-in is sent unchanged', () async {
      final hosts = _Hosts(_Kind.portal,
          now: _t0.add(const Duration(minutes: 61)), keptSignIn: false);
      final token = hosts.tokens.schedulerToken;

      expect(await hosts.sessions.tokenForRequest(), token);
      expect(hosts.refreshes, 0);
    });

    test('a server or network failure keeps the refresh token', () async {
      final tokens = FakeTokens(
          schedulerToken: _portalToken(_t0), refreshToken: 'refresh-0');
      final sessions = SessionRotator(
        tokens: tokens,
        essTokens: tokens,
        refreshDio: Dio(BaseOptions(baseUrl: _env.essBaseUrl))
          ..httpClientAdapter = ScriptedAdapter((_) =>
              jsonReply(503, {'error': 'Try again.', 'code': 'UNAVAILABLE'})),
      );

      expect(await sessions.renew(), isFalse);
      expect(tokens.refreshToken, 'refresh-0');
    });

    test('a reply with no tokens drops the kept sign-in', () async {
      final tokens = FakeTokens(
          schedulerToken: _portalToken(_t0), refreshToken: 'refresh-0');
      final sessions = SessionRotator(
        tokens: tokens,
        essTokens: tokens,
        refreshDio: Dio(BaseOptions(baseUrl: _env.essBaseUrl))
          ..httpClientAdapter =
              ScriptedAdapter((_) => jsonReply(200, {'session': {}})),
      );

      expect(await sessions.renew(), isFalse);
      expect(tokens.refreshToken, isNull);
    });

    test('verdictFor reads the code first, then the old string rules', () {
      final now = _t0.add(const Duration(minutes: 5));
      final portal = _portalToken(_t0.add(const Duration(hours: 1)));
      final attendance = _attendanceToken(_t0.add(const Duration(hours: 1)));
      final spentAttendance = _attendanceToken(_t0);
      SessionVerdict v(Object? body, [String? token]) =>
          SessionRotator.verdictFor(body, sentToken: token ?? portal, now: now);

      expect(v({'code': 'NO_TOKEN'}), SessionVerdict.over);
      expect(v({'code': 'USER_NOT_FOUND'}), SessionVerdict.over);
      expect(v({'code': 'ACCOUNT_EXITED'}), SessionVerdict.over);
      expect(v({'code': 'PASSWORD_CHANGED'}), SessionVerdict.over);
      expect(v({'code': 'TOKEN_EXPIRED'}), SessionVerdict.renew);
      expect(v({'code': 'INVALID_TOKEN'}), SessionVerdict.renew);
      expect(v({'code': 'NOT_AUTHENTICATED'}), SessionVerdict.renew);
      expect(v({'code': 'INVALID_TOKEN'}, attendance), SessionVerdict.renewOrKeep);
      expect(v({'code': 'INVALID_TOKEN'}, spentAttendance), SessionVerdict.renew);
      expect(v({'code': 'WRONG_PASSWORD'}), SessionVerdict.keep);
      // No code: the rules the Scheduler client had before.
      expect(v({'error': 'Please authenticate'}), SessionVerdict.over);
      expect(v({'error': 'No token provided'}), SessionVerdict.over);
      expect(v('<html>Unauthorized</html>'), SessionVerdict.over);
      expect(v({'error': 'Invalid password'}), SessionVerdict.keep);
      expect(v({'error': 'Invalid password'}, _portalToken(_t0)),
          SessionVerdict.renew,
          reason: 'a token past its exp is renewed');
    });

    test('reads the token kind and expiry without checking the signature', () {
      expect(SessionRotator.isAttendanceToken(_attendanceToken(_t0)), isTrue);
      expect(SessionRotator.isAttendanceToken(_portalToken(_t0)), isFalse);
      expect(SessionRotator.isAttendanceToken('not-a-jwt'), isFalse);
      expect(SessionRotator.expiryOf(_portalToken(_t0)), _t0);
      expect(SessionRotator.expiryOf(null), isNull);
    });
  });
}

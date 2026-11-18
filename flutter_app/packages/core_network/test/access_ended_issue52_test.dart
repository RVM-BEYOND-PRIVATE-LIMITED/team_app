import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// team_app #52, item 8: when the server says the person's access has ended
/// (an exited account, a changed password: the two the issue names), the
/// session is over and the server's own message reaches the sign-in screen.
/// Every other refusal keeps today's behaviour, a 403 `NOT_ACTIVE` included:
/// it reaches the screen that asked and the session stays.
///
/// The codes and messages are the servers' own on main:
///  * Scheduler_Backend middleware/auth.js: 401 ACCOUNT_EXITED, 401
///    PASSWORD_CHANGED; controllers/hr/attendancePunchController.js: 403
///    NOT_ACTIVE.
///  * team_app apps/ess-api src/middleware/employeeAuth.js: 403 NOT_ACTIVE;
///    src/routes/sessions.js: a refused refresh, 401 NOT_AUTHENTICATED with a
///    `reason` (`left`, `password_changed`, ...); src/lib/errors.js: the
///    messages.
const _env = ApiEnvironment(
  schedulerBaseUrl: 'https://scheduler.test/api',
  jobPortalBaseUrl: 'https://jobs.test/api/v1',
  essBaseUrl: 'https://ess.test/api/ess',
);

const _exited =
    'This account has been marked exited. Contact a Super Admin if you need '
    'access restored.';
const _passwordChanged = 'Your password was changed. Please sign in again.';
const _punchNotActive =
    'Your employee record is not active, so punching is closed.';
const _essNotActive =
    'Your employee record is no longer active, so Team RVM is closed for this '
    'login. Ask HR if this is wrong.';

/// What the ESS answers a refused refresh with, per reason (routes/sessions.js
/// REFUSED).
const _refusedRefresh = {
  'left': _essNotActive,
  'password_changed': _passwordChanged,
  'expired': 'Your sign-in has expired. Please sign in again.',
  'signed_out': 'You have signed out. Please sign in again.',
};

final _now = DateTime.utc(2026, 11, 13, 9);

String _token(DateTime exp) => fakeJwt({
      'userId': 'u-test',
      'role': 'faculty',
      'iat': epochSeconds(_now.subtract(const Duration(minutes: 30))),
      'exp': epochSeconds(exp),
    });

/// The app's validateStatus for each client (rvm_team_app lib/injection.dart):
/// every refusal but a 401 comes back as a reply, not a thrown error.
bool _appScheduler(int? s) => s != null && s != 401;
bool _appEss(int? s) =>
    s != null && ((s >= 200 && s < 300) || (s >= 400 && s != 401));

class _World {
  _World({
    bool live = true,
    bool keptSignIn = false,
    this.refreshRefusal,
    bool signedIn = true,
  }) {
    tokens = FakeTokens(
      schedulerToken: signedIn
          ? _token(live ? _now.add(const Duration(hours: 1)) : _now)
          : null,
      refreshToken: keptSignIn ? 'refresh-0' : null,
    );
    sessions = SessionRotator(
      tokens: tokens,
      essTokens: tokens,
      refreshDio: Dio(BaseOptions(baseUrl: _env.essBaseUrl))
        ..httpClientAdapter = refresh,
      clock: () => _now,
    );
  }

  late final FakeTokens tokens;
  late final SessionRotator sessions;

  /// The reason the ESS refuses every refresh with, or null to renew.
  String? refreshRefusal;

  late final ScriptedAdapter refresh = ScriptedAdapter((_) {
    final reason = refreshRefusal;
    if (reason == null) {
      final exp = _now.add(const Duration(hours: 1));
      return jsonReply(200, {
        'access_token': _token(exp),
        'access_expires_at': exp.toIso8601String(),
        'refresh_token': 'refresh-1',
      });
    }
    return jsonReply(401, {
      'error': _refusedRefresh[reason] ?? 'Please sign in again.',
      'code': 'NOT_AUTHENTICATED',
      'reason': reason,
    });
  });

  /// The Scheduler client as the app builds it, answering [status]/[body].
  Dio scheduler(int status, Map<String, Object?> body,
          {bool Function(int?) validateStatus = _appScheduler}) =>
      DioFactory.scheduler(env: _env, tokens: tokens, sessions: sessions)
        ..httpClientAdapter = ScriptedAdapter((_) => jsonReply(status, body))
        ..options.validateStatus = validateStatus;

  /// The ESS client as the app builds it, answering [status]/[body].
  Dio ess(int status, Map<String, Object?> body) => DioFactory.ess(
        env: _env,
        tokens: tokens,
        essTokens: tokens,
        sessions: sessions,
      )
        ..httpClientAdapter = ScriptedAdapter((_) => jsonReply(status, body))
        ..options.validateStatus = _appEss;
}

Future<void> _get(Dio dio, [String path = '/x']) async {
  try {
    await dio.get<dynamic>(path);
  } on DioException catch (_) {}
}

void main() {
  group('Scheduler client', () {
    for (final (code, message) in [
      ('ACCOUNT_EXITED', _exited),
      ('PASSWORD_CHANGED', _passwordChanged),
    ]) {
      test('401 $code ends the session with the server\'s message', () async {
        final world = _World(keptSignIn: true);

        await _get(world.scheduler(401, {'error': message, 'code': code}));

        expect(world.tokens.messages, [message]);
        expect(world.tokens.refreshToken, isNull,
            reason: 'both halves of the session end');
        expect(world.refresh.seen, isEmpty, reason: 'no renewal can help');
      });
    }

    // Not one of the issue's two codes: the punch card shows its refusal
    // inline and the session stays, as before.
    test('403 NOT_ACTIVE reaches the punch screen and keeps the session',
        () async {
      final world = _World(keptSignIn: true);
      final dio = world
          .scheduler(403, {'error': _punchNotActive, 'code': 'NOT_ACTIVE'});

      final res = await dio.post<dynamic>('/hr/my-attendance/punch');

      expect(res.statusCode, 403);
      expect((res.data as Map)['error'], _punchNotActive);
      expect(world.tokens.unauthorized, 0);
      expect(world.tokens.refreshToken, 'refresh-0');
    });

    test('403 NOT_ACTIVE keeps it too when the client throws refusals',
        () async {
      final world = _World(keptSignIn: true);
      final dio = world.scheduler(
          403, {'error': _punchNotActive, 'code': 'NOT_ACTIVE'},
          validateStatus: (s) => s != null && s >= 200 && s < 300);

      final error = await dio
          .post<dynamic>('/hr/my-attendance/punch')
          .then<DioException?>((_) => null,
              onError: (Object e) => e as DioException);

      expect(error?.response?.statusCode, 403);
      expect(world.tokens.unauthorized, 0);
      expect(world.tokens.refreshToken, 'refresh-0');
    });

    test('a refused sign-in code (no token sent) is the sign-in screen\'s',
        () async {
      final world = _World(signedIn: false);

      await _get(world
          .scheduler(403, {'error': _punchNotActive, 'code': 'NOT_ACTIVE'}));

      expect(world.tokens.unauthorized, 0);
    });

    for (final body in [
      {'error': 'Access denied. Insufficient privileges.'},
      {
        'error': 'Sales executives can only use the sales dialer.',
        'code': 'SALES_WORKSPACE_ONLY',
      },
      {
        'error': 'Your login is not linked to an employee record yet.',
        'code': 'NOT_LINKED',
      },
    ]) {
      test('403 ${body['code'] ?? body['error']} keeps the session', () async {
        final world = _World();

        await _get(world.scheduler(403, body));

        expect(world.tokens.unauthorized, 0);
      });
    }

    test('an ordinary expiry still ends the session with no message', () async {
      final world = _World(live: false);

      await _get(world.scheduler(401, {
        'error': 'Your session has expired. Please sign in again.',
        'code': 'TOKEN_EXPIRED',
      }));

      expect(world.tokens.messages, [null]);
    });

    test('a controller 401 with a live token keeps the session', () async {
      final world = _World();

      await _get(world
          .scheduler(401, {'error': 'Authentication required with location.'}));

      expect(world.tokens.unauthorized, 0);
    });

    for (final (reason, message) in [
      ('left', _essNotActive),
      ('password_changed', _passwordChanged),
    ]) {
      test('a renewal refused because "$reason" shows the ESS\'s message',
          () async {
        final world = _World(keptSignIn: true, refreshRefusal: reason);

        await _get(world.scheduler(401, {
          'error': 'Your session has expired. Please sign in again.',
          'code': 'TOKEN_EXPIRED',
        }));

        expect(world.refresh.seen, hasLength(1));
        expect(world.tokens.messages, [message]);
      });
    }

    for (final reason in ['expired', 'signed_out']) {
      test('a renewal refused because "$reason" ends it with no message',
          () async {
        final world = _World(keptSignIn: true, refreshRefusal: reason);

        await _get(world.scheduler(401, {
          'error': 'Your session has expired. Please sign in again.',
          'code': 'TOKEN_EXPIRED',
        }));

        expect(world.tokens.messages, [null]);
      });
    }

    // The everyday path: the hourly token is spent, so it is renewed before
    // the request is sent. The refused renewal leaves the old token to send,
    // and the 401 it draws is what ends the session, with the ESS's reason.
    for (final (reason, message) in [
      ('left', _essNotActive),
      ('password_changed', _passwordChanged),
      ('expired', null),
      ('signed_out', null),
    ]) {
      test(
          'a spent token whose renewal is refused because "$reason" ends '
          'with ${message == null ? 'no message' : 'the ESS\'s message'}',
          () async {
        final world =
            _World(live: false, keptSignIn: true, refreshRefusal: reason);

        await _get(world.scheduler(401, {
          'error': 'Your session has expired. Please sign in again.',
          'code': 'TOKEN_EXPIRED',
        }));

        expect(world.refresh.seen, hasLength(1),
            reason: 'renewed once, before sending');
        expect(world.tokens.messages, [message]);
        expect(world.tokens.refreshToken, isNull);
        expect(world.sessions.refusalMessage, isNull,
            reason: 'the reason is used once, by the session it ended');
      });
    }

    test('a refusal in a token\'s last seconds shows on the 401 that follows',
        () async {
      final world =
          _World(keptSignIn: true, refreshRefusal: 'password_changed');
      // Inside the renewal leeway, so renewed before sending, but the server
      // still takes it.
      world.tokens.schedulerToken =
          _token(_now.add(const Duration(seconds: 20)));
      var calls = 0;
      final dio = world.scheduler(200, const {})
        ..httpClientAdapter = ScriptedAdapter((_) => ++calls == 1
            ? jsonReply(200, {'ok': true})
            : jsonReply(401, {
                'error': 'Your session has expired. Please sign in again.',
                'code': 'TOKEN_EXPIRED',
              }));

      await _get(dio);
      expect(world.tokens.unauthorized, 0);

      await _get(dio);
      expect(world.refresh.seen, hasLength(1));
      expect(world.tokens.messages, [_passwordChanged]);
    });
  });

  group('ESS client', () {
    // Not one of the issue's two codes: the screen that asked shows it (the
    // shell's access screen for capabilities) and the session stays.
    test('403 NOT_ACTIVE reaches the screen and keeps the session', () async {
      final world = _World(keptSignIn: true);
      final dio =
          world.ess(403, {'error': _essNotActive, 'code': 'NOT_ACTIVE'});

      final res = await dio.get<dynamic>('/me/capabilities');

      expect(res.statusCode, 403);
      expect((res.data as Map)['error'], _essNotActive);
      expect(world.tokens.unauthorized, 0);
      expect(world.tokens.refreshToken, 'refresh-0');
    });

    test('403 NOT_ACTIVE keeps it too when the client throws refusals',
        () async {
      final world = _World(keptSignIn: true);
      final dio = world.ess(403, {'error': _essNotActive, 'code': 'NOT_ACTIVE'})
        ..options.validateStatus = (s) => s != null && s >= 200 && s < 300;

      await _get(dio, '/me');

      expect(world.tokens.unauthorized, 0);
      expect(world.tokens.refreshToken, 'refresh-0');
    });

    test('a refresh refused because the password changed says so', () async {
      final world =
          _World(keptSignIn: true, refreshRefusal: 'password_changed');

      await _get(world.ess(401,
          {'error': 'Please sign in again.', 'code': 'NOT_AUTHENTICATED'}));

      expect(world.tokens.messages, [_passwordChanged]);
    });

    test('a refresh refused for another reason ends it with no message',
        () async {
      final world = _World(keptSignIn: true, refreshRefusal: 'signed_out');

      await _get(world.ess(401,
          {'error': 'Please sign in again.', 'code': 'NOT_AUTHENTICATED'}));

      expect(world.tokens.messages, [null]);
    });

    for (final (reason, message) in [
      ('left', _essNotActive),
      ('password_changed', _passwordChanged),
      ('expired', null),
      ('signed_out', null),
    ]) {
      test(
          'a spent token whose renewal is refused because "$reason" ends '
          'with ${message == null ? 'no message' : 'the ESS\'s message'}',
          () async {
        final world =
            _World(live: false, keptSignIn: true, refreshRefusal: reason);

        await _get(world.ess(401,
            {'error': 'Please sign in again.', 'code': 'NOT_AUTHENTICATED'}));

        expect(world.refresh.seen, hasLength(1),
            reason: 'renewed once, before sending');
        expect(world.tokens.messages, [message]);
        expect(world.tokens.refreshToken, isNull);
      });
    }

    test('403 NOT_LINKED keeps the session', () async {
      final world = _World();

      await _get(world.ess(403, {
        'error': 'Your login is not linked to an employee record yet.',
        'code': 'NOT_LINKED',
      }));

      expect(world.tokens.unauthorized, 0);
    });

    test('the kept-sign-in exchange never signs out, even on NOT_ACTIVE',
        () async {
      final world = _World();
      final dio =
          world.ess(403, {'error': _essNotActive, 'code': 'NOT_ACTIVE'});

      await dio.post<dynamic>('/session');

      expect(world.tokens.unauthorized, 0);
    });
  });

  group('SessionRotator', () {
    test('accessEndedMessage reads only the codes and reasons that end access',
        () {
      String? m(Object? body) => SessionRotator.accessEndedMessage(body);

      expect(m({'error': _exited, 'code': 'ACCOUNT_EXITED'}), _exited);
      expect(m({'error': _passwordChanged, 'code': 'PASSWORD_CHANGED'}),
          _passwordChanged);
      // A 403 NOT_ACTIVE is the asking screen's to show, not a sign-out.
      expect(m({'error': _essNotActive, 'code': 'NOT_ACTIVE'}), isNull);
      expect(m({'error': _punchNotActive, 'code': 'NOT_ACTIVE'}), isNull);
      expect(
          m({
            'error': _essNotActive,
            'code': 'NOT_AUTHENTICATED',
            'reason': 'left',
          }),
          _essNotActive);
      expect(
          m({
            'error': _passwordChanged,
            'code': 'NOT_AUTHENTICATED',
            'reason': 'password_changed',
          }),
          _passwordChanged);
      // Not about access ending: today's silent return to sign-in.
      expect(
          m({'error': 'Please authenticate', 'code': 'INVALID_TOKEN'}), isNull);
      expect(
          m({'error': 'Please sign in again.', 'reason': 'expired'}), isNull);
      expect(m({'error': 'Please authenticate'}), isNull);
      // A code with no words to show.
      expect(m({'code': 'ACCOUNT_EXITED'}), isNull);
      expect(m({'error': '  ', 'code': 'ACCOUNT_EXITED'}), isNull);
      expect(m('<html>Unauthorized</html>'), isNull);
      expect(m(null), isNull);
    });

    test('the codes that end access are exactly the issue\'s two', () {
      expect(SessionRotator.accessEndedCodes,
          {'ACCOUNT_EXITED', 'PASSWORD_CHANGED'});
      expect(SessionRotator.accessEndedReasons, {'left', 'password_changed'});
    });

    test('a refusal stands through a renewal with nothing left to send',
        () async {
      final world = _World(keptSignIn: true, refreshRefusal: 'left');

      expect(await world.sessions.renew(), isFalse);
      expect(world.sessions.refusalMessage, _essNotActive);

      // The kept sign-in is gone, so the next renewal has nothing to send. It
      // is still the refused sign-in, so the reason still stands.
      expect(await world.sessions.renew(), isFalse);
      expect(world.sessions.refusalMessage, _essNotActive);
      expect(world.refresh.seen, hasLength(1));
    });

    test('a refusal ends with the session', () async {
      final world = _World(keptSignIn: true, refreshRefusal: 'left');

      expect(await world.sessions.renew(), isFalse);
      await world.sessions.endSession(message: world.sessions.refusalMessage);

      expect(world.sessions.refusalMessage, isNull);
      expect(world.tokens.messages, [_essNotActive]);
    });

    test('a refusal never reaches a later sign-in', () async {
      final world =
          _World(keptSignIn: true, refreshRefusal: 'password_changed');

      expect(await world.sessions.renew(), isFalse);
      expect(world.sessions.refusalMessage, _passwordChanged);

      // Signed out some other way, then signed in again with no kept sign-in.
      world.tokens.schedulerToken =
          _token(_now.add(const Duration(minutes: 5)));

      expect(await world.sessions.renew(), isFalse);
      expect(world.sessions.refusalMessage, isNull);
    });

    for (final (next, renewed) in [(null, true), ('expired', false)]) {
      test(
          'a refresh sent again clears an earlier refusal '
          '(${next ?? 'renewed'})', () async {
        final world = _World(keptSignIn: true, refreshRefusal: 'left');

        expect(await world.sessions.renew(), isFalse);
        expect(world.sessions.refusalMessage, _essNotActive);

        // A new kept sign-in on the same token, and the ESS's next answer.
        world.tokens.refreshToken = 'refresh-new';
        world.refreshRefusal = next;

        expect(await world.sessions.renew(), renewed);
        expect(world.refresh.seen, hasLength(2));
        expect(world.sessions.refusalMessage, isNull);
      });
    }

    test('a refresh that succeeds leaves no refusal', () async {
      final world = _World(keptSignIn: true);

      expect(await world.sessions.renew(), isTrue);
      expect(world.sessions.refusalMessage, isNull);
    });

    test('endSession hands the message to the token store', () async {
      final world = _World(keptSignIn: true);

      await world.sessions.endSession(message: _exited);
      await world.sessions.endSession();

      expect(world.tokens.messages, [_exited, null]);
      expect(world.tokens.refreshToken, isNull);
    });
  });
}

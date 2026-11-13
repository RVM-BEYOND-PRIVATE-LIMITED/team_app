import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// team_app #50 item 5: the modules list (`GET /api/me/features`) is an
/// optional read. Its 401 must never sign the person out, whatever the reply
/// says, while every other request keeps today's rules. A request opts in
/// with [BearerAuthInterceptor.keepSessionKey].

final _now = DateTime.utc(2026, 11, 13, 9);

const _env = ApiEnvironment(
  schedulerBaseUrl: 'https://scheduler.test/api',
  jobPortalBaseUrl: 'https://jobs.test/api/v1',
  essBaseUrl: 'https://ess.test/api/ess',
);

String _token(String id) => fakeJwt({
      'userId': 'u-test',
      'jti': id,
      'iat': epochSeconds(_now),
      'exp': epochSeconds(_now.add(const Duration(hours: 1))),
    });

final _keep = Options(extra: {BearerAuthInterceptor.keepSessionKey: true});

/// The Scheduler client as the app builds it (rvm_team_app lib/injection.dart),
/// with a kept sign-in whose refresh answers [refresh].
class _Client {
  _Client({
    required ResponseBody Function(RequestOptions o) scheduler,
    ResponseBody Function(RequestOptions o)? refresh,
  }) {
    tokens = FakeTokens(schedulerToken: _token('t0'), refreshToken: 'r0');
    refreshHost = ScriptedAdapter(refresh ??
        (_) => jsonReply(401, {'error': 'Sign in again.', 'code': 'X'}));
    schedulerHost = ScriptedAdapter(scheduler);
    final sessions = SessionRotator(
      tokens: tokens,
      essTokens: tokens,
      refreshDio: Dio(BaseOptions(baseUrl: _env.essBaseUrl))
        ..httpClientAdapter = refreshHost,
      clock: () => _now,
    );
    dio = DioFactory.scheduler(env: _env, tokens: tokens, sessions: sessions)
      ..httpClientAdapter = schedulerHost
      ..options.validateStatus = (s) => s != null && s != 401;
  }

  late final FakeTokens tokens;
  late final ScriptedAdapter refreshHost;
  late final ScriptedAdapter schedulerHost;
  late final Dio dio;

  Future<Object?> features() async {
    try {
      return (await dio.get<Object?>('/me/features', options: _keep)).data;
    } on DioException catch (e) {
      return e.error;
    }
  }

  Future<Object?> plain() async {
    try {
      return (await dio.get<Object?>('/me')).data;
    } on DioException catch (e) {
      return e.error;
    }
  }
}

void main() {
  // Each 401 body the Scheduler can send on GET /api/me/features
  // (middleware/auth.js, middleware/staffOnly.js on develop) that ends the
  // session for an ordinary request.
  final sessionEnding = <String, Map<String, Object?>>{
    'NO_TOKEN': {'error': 'No token provided', 'code': 'NO_TOKEN'},
    'USER_NOT_FOUND': {
      'error': 'Please authenticate',
      'code': 'USER_NOT_FOUND'
    },
    'ACCOUNT_EXITED': {
      'error': 'Your access has ended.',
      'code': 'ACCOUNT_EXITED'
    },
    'PASSWORD_CHANGED': {
      'error': 'Your password was changed. Please sign in again.',
      'code': 'PASSWORD_CHANGED'
    },
    'staffOnly, no code': {'error': 'Please authenticate'},
  };

  group('a request with keepSessionKey', () {
    for (final entry in sessionEnding.entries) {
      test('401 ${entry.key}: reaches the caller, nobody is signed out',
          () async {
        final client = _Client(scheduler: (_) => jsonReply(401, entry.value));

        final result = await client.features();

        expect(result, isA<UnauthorizedFailure>());
        expect(client.tokens.unauthorized, 0);
        expect(client.tokens.schedulerToken, isNotNull);
        expect(client.tokens.refreshToken, 'r0');
        expect(client.schedulerHost.seen, hasLength(1));
      });
    }

    test('the same 401 on an ordinary request still ends the session',
        () async {
      for (final body in sessionEnding.values) {
        final client = _Client(scheduler: (_) => jsonReply(401, body));
        await client.plain();
        expect(client.tokens.unauthorized, 1, reason: '$body');
      }
    });

    test('an expired token is still renewed once and the request sent again',
        () async {
      final client = _Client(
        scheduler: (o) => o.headers['Authorization'] == 'Bearer ${_token('t1')}'
            ? jsonReply(200, {
                'features': [
                  {'key': 'crm', 'dry_run': false}
                ]
              })
            : jsonReply(401, {
                'error': 'Your session has expired. Please sign in again.',
                'code': 'TOKEN_EXPIRED'
              }),
        refresh: (_) => jsonReply(200, {
          'access_token': _token('t1'),
          'refresh_token': 'r1',
        }),
      );

      final result = await client.features();

      expect(result, {
        'features': [
          {'key': 'crm', 'dry_run': false}
        ]
      });
      expect(client.refreshHost.seen, hasLength(1));
      expect(client.schedulerHost.seen, hasLength(2));
      expect(client.tokens.unauthorized, 0);
    });

    test('a refused renewal does not sign the person out', () async {
      final client = _Client(
        scheduler: (_) => jsonReply(401, {
          'error': 'Your session has expired. Please sign in again.',
          'code': 'TOKEN_EXPIRED'
        }),
        refresh: (_) =>
            jsonReply(401, {'error': 'Sign in again.', 'reason': 'expired'}),
      );

      final result = await client.features();

      expect(result, isA<UnauthorizedFailure>());
      expect(client.tokens.unauthorized, 0);
      expect(client.tokens.schedulerToken, isNotNull);
      // The rotator drops a refresh token the server has refused, as it does
      // for any request: it cannot renew anything again. The session itself
      // is left to the next ordinary request.
      expect(client.tokens.refreshToken, isNull);
      expect(client.schedulerHost.seen, hasLength(1));
    });

    test('a renewed token that is refused too: still nobody signed out',
        () async {
      final client = _Client(
        scheduler: (_) => jsonReply(401, {
          'error': 'Please authenticate',
          'code': 'INVALID_TOKEN',
        }),
        refresh: (_) => jsonReply(200, {
          'access_token': _token('t1'),
          'refresh_token': 'r1',
        }),
      );

      final result = await client.features();

      expect(result, isA<UnauthorizedFailure>());
      expect(client.tokens.unauthorized, 0);
      // One renewal, one replay: no loop.
      expect(client.refreshHost.seen, hasLength(1));
      expect(client.schedulerHost.seen, hasLength(2));
    });

    test('the flag belongs to its request only', () async {
      final client = _Client(
          scheduler: (_) => jsonReply(
              401, {'error': 'No token provided', 'code': 'NO_TOKEN'}));

      await client.features();
      expect(client.tokens.unauthorized, 0);

      await client.plain();
      expect(client.tokens.unauthorized, 1);
    });

    test('a non-401 reply is untouched', () async {
      final client = _Client(
          scheduler: (_) =>
              jsonReply(403, {'error': 'Access denied. Staff only.'}));

      final result = await client.features();

      expect(result, {'error': 'Access denied. Staff only.'});
      expect(client.tokens.unauthorized, 0);
      expect(client.refreshHost.seen, isEmpty);
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/team_modules_bloc.dart';
import 'package:rvm_team_app/data/datasources/team_modules_remote_data_source.dart';
import 'package:rvm_team_app/data/repositories/team_modules_repository.dart';
import 'package:rvm_team_app/domain/team_modules.dart';
import 'package:rvm_team_app/router/module_routes.dart';

/// team_app #50 item 5: which staff modules are open, from the Scheduler's
/// `GET /api/me/features` (Scheduler_Backend routes/meFeatures.js, develop).
/// Any failure is "no modules", and the request can never end the session.

class _MockConnectivity extends Mock implements ConnectivityService {}

// ── the Scheduler, faked ─────────────────────────────────────────────────

const _env = ApiEnvironment(
  schedulerBaseUrl: 'https://scheduler.test/api',
  jobPortalBaseUrl: 'https://jobs.test/api/v1',
  essBaseUrl: 'https://ess.test/api/ess',
);

/// One expiry for every token of a run, an hour ahead, so no token is
/// renewed before it is sent.
final _exp = DateTime.now().add(const Duration(hours: 1));

String _jwt(String id) {
  final claims = {
    'userId': 'u-test',
    'jti': id,
    'exp': _exp.millisecondsSinceEpoch ~/ 1000,
  };
  return 'h.${base64Url.encode(utf8.encode(json.encode(claims))).replaceAll('=', '')}.s';
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      json.encode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// Answers from a script and records every request.
class _Host implements HttpClientAdapter {
  _Host(this.answer);

  final FutureOr<ResponseBody> Function(RequestOptions o) answer;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options);
    return answer(options);
  }

  @override
  void close({bool force = false}) {}
}

/// The session as the network layer sees it (AuthSession in the app),
/// counting every way a session can end.
class _Session implements TokenStore, EssTokenStore {
  String? token = _jwt('t0');
  String? refresh = 'r0';
  int signedOut = 0;
  int keptSignInCleared = 0;

  @override
  Future<String?> readSchedulerToken() async => token;

  @override
  Future<void> onUnauthorized({String? message}) async {
    signedOut++;
    token = null;
  }

  @override
  Future<String?> readEssRefreshToken() async => refresh;

  @override
  Future<String> installId() async => 'install-1';

  @override
  Future<void> saveEssSession({
    required String accessToken,
    required String refreshToken,
    DateTime? accessExpiresAt,
  }) async {
    token = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clearEssSession() async {
    keptSignInCleared++;
    refresh = null;
  }
}

/// The repository on the app's own Scheduler client (DioFactory.scheduler,
/// with the validateStatus rvm_team_app lib/injection.dart sets), the shared
/// renewal, and a kept sign-in whose refresh answers [refresh].
class _Rig {
  _Rig(
    FutureOr<ResponseBody> Function(RequestOptions o) scheduler, {
    FutureOr<ResponseBody> Function(RequestOptions o)? refresh,
    bool online = true,
  }) {
    host = _Host(scheduler);
    refreshHost = _Host(refresh ??
        (_) => _json(401, {'error': 'Sign in again.', 'reason': 'expired'}));
    final sessions = SessionRotator(
      tokens: session,
      essTokens: session,
      refreshDio: Dio(BaseOptions(baseUrl: _env.essBaseUrl))
        ..httpClientAdapter = refreshHost,
    );
    final dio =
        DioFactory.scheduler(env: _env, tokens: session, sessions: sessions)
          ..httpClientAdapter = host
          ..options.validateStatus = (s) => s != null && s != 401;
    final connectivity = _MockConnectivity();
    when(() => connectivity.isOnline).thenAnswer((_) async => online);
    remote = TeamModulesRemoteDataSource(dio);
    repository =
        TeamModulesRepository(remote: remote, connectivity: connectivity);
  }

  final session = _Session();
  late final _Host host;
  late final _Host refreshHost;
  late final TeamModulesRemoteDataSource remote;
  late final TeamModulesRepository repository;
}

const _staffOnly = {'error': 'Access denied. Staff only.'};

/// What production (Scheduler_Backend main, no /api/me/features yet)
/// answers: the /api catch-all of server.js.
const _productionUnknownPath = {
  'error': 'API endpoint not found.',
  'code': 'NOT_FOUND'
};

void main() {
  group('TeamModules.fromJson', () {
    test('reads the documented reply, dry_run included', () {
      final modules = TeamModules.fromJson({
        'features': [
          {'key': 'crm', 'dry_run': false},
          {'key': 'fees', 'dry_run': true},
        ],
      });
      expect(modules.open, {TeamModule.crm, TeamModule.fees});
      expect(modules.has(TeamModule.crm), isTrue);
      expect(modules.isDryRun(TeamModule.crm), isFalse);
      expect(modules.isDryRun(TeamModule.fees), isTrue);
      expect(modules.has(TeamModule.tasks), isFalse);
      expect(modules.isDryRun(TeamModule.tasks), isFalse);
    });

    test('only a true dry_run is dry, as the server sends it', () {
      final modules = TeamModules.fromJson({
        'features': [
          {'key': 'crm'},
          {'key': 'fees', 'dry_run': 'true'},
          {'key': 'ops', 'dry_run': 1},
          {'key': 'desk', 'dry_run': null},
        ],
      });
      expect(modules.open,
          {TeamModule.crm, TeamModule.fees, TeamModule.ops, TeamModule.desk});
      for (final module in modules.open) {
        expect(modules.isDryRun(module), isFalse, reason: '$module');
      }
    });

    test('every module is named by its key, one key each', () {
      expect([
        for (final m in TeamModule.values) m.key
      ], [
        'crm',
        'fees',
        'ops',
        'desk',
        'placement',
        'scorecards',
        'tasks',
        'social',
        'complaints',
        'moderation',
      ]);
      for (final module in TeamModule.values) {
        expect(module.routePrefix, '/${module.key}');
        expect(teamModuleForKey(module.key), module);
      }
      final all = TeamModules.fromJson({
        'features': [
          for (final m in TeamModule.values) {'key': m.key, 'dry_run': false}
        ],
      });
      expect(all.open, TeamModule.values.toSet());
    });

    test('unknown keys are ignored, and keys match exactly', () {
      final modules = TeamModules.fromJson({
        'features': [
          {'key': 'reports', 'dry_run': false},
          {'key': 'CRM', 'dry_run': false},
          {'key': ' crm', 'dry_run': false},
          {'key': '/crm', 'dry_run': false},
          {'key': 'tasks', 'dry_run': true},
        ],
      });
      expect(modules.open, {TeamModule.tasks});
      expect(teamModuleForKey('CRM'), isNull);
      expect(teamModuleForKey(null), isNull);
      expect(teamModuleForKey(7), isNull);
    });

    test('a body that is not the documented shape opens nothing', () {
      for (final body in <Object?>[
        null,
        '',
        '<html>Bad gateway</html>',
        42,
        const [],
        const <String, Object?>{},
        {'features': null},
        {'features': 'crm'},
        {
          'features': {'crm': true}
        },
        {
          'modules': const ['crm']
        },
        {'features': const []},
        {
          'features': [
            1,
            'crm',
            null,
            {'key': 3},
            {'name': 'crm'},
          ]
        },
      ]) {
        final modules = TeamModules.fromJson(body);
        expect(modules, TeamModules.none, reason: '$body');
        expect(modules.isEmpty, isTrue, reason: '$body');
      }
    });

    test('a bad entry is skipped, the good ones still open', () {
      final modules = TeamModules.fromJson({
        'features': [
          'crm',
          {'key': 'social', 'dry_run': false},
        ],
      });
      expect(modules.open, {TeamModule.social});
    });

    test('equal replies are equal, whatever the order', () {
      final a = TeamModules.fromJson({
        'features': [
          {'key': 'crm', 'dry_run': true},
          {'key': 'fees', 'dry_run': false},
        ],
      });
      final b = TeamModules({TeamModule.fees: false, TeamModule.crm: true});
      expect(a, b);
      expect(a,
          isNot(TeamModules({TeamModule.fees: false, TeamModule.crm: false})));
      expect(TeamModules.none.open, isEmpty);
    });
  });

  group('the data source and repository', () {
    test('200: asks GET /api/me/features with the bearer and reads it',
        () async {
      final rig = _Rig((_) => _json(200, {
            'features': [
              {'key': 'crm', 'dry_run': true},
              {'key': 'unknown_module', 'dry_run': false},
            ],
          }));

      final modules = await rig.repository.modules();

      expect(modules.open, {TeamModule.crm});
      expect(modules.isDryRun(TeamModule.crm), isTrue);
      final sent = rig.host.seen.single;
      expect(sent.method, 'GET');
      expect(sent.uri.toString(), 'https://scheduler.test/api/me/features');
      expect(sent.headers['Authorization'], 'Bearer ${_jwt('t0')}');
      expect(sent.extra[BearerAuthInterceptor.keepSessionKey], isTrue);
    });

    test('200 with nothing open: no modules', () async {
      final rig = _Rig((_) => _json(200, {'features': const []}));
      expect(await rig.repository.modules(), TeamModules.none);
    });

    // Every 401 the route can send (middleware/auth.js, staffOnly.js).
    final unauthorized = <String, Map<String, Object?>>{
      'NO_TOKEN': {'error': 'No token provided', 'code': 'NO_TOKEN'},
      'INVALID_TOKEN': {
        'error': 'Please authenticate',
        'code': 'INVALID_TOKEN'
      },
      'TOKEN_EXPIRED': {
        'error': 'Your session has expired. Please sign in again.',
        'code': 'TOKEN_EXPIRED'
      },
      'USER_NOT_FOUND': {
        'error': 'Please authenticate',
        'code': 'USER_NOT_FOUND'
      },
      'ACCOUNT_EXITED': {
        'error': 'Your access has ended.',
        'code': 'ACCOUNT_EXITED'
      },
      'PASSWORD_CHANGED': {
        'error': 'Your password was changed.',
        'code': 'PASSWORD_CHANGED'
      },
      'staffOnly, no code': {'error': 'Please authenticate'},
    };
    for (final entry in unauthorized.entries) {
      test('401 ${entry.key}: no modules, and the session is not ended',
          () async {
        final rig = _Rig((_) => _json(401, entry.value));

        expect(await rig.repository.modules(), TeamModules.none);
        expect(rig.session.signedOut, 0);
        expect(rig.session.token, isNotNull);
        // At most one renewal and one replay: never a loop.
        expect(rig.refreshHost.seen.length, lessThanOrEqualTo(1));
        expect(rig.host.seen.length, lessThanOrEqualTo(2));
      });
    }

    test('401 after a renewal that worked: still no sign-out', () async {
      final rig = _Rig(
        (_) => _json(
            401, {'error': 'Please authenticate', 'code': 'INVALID_TOKEN'}),
        refresh: (_) => _json(200, {
          'access_token': _jwt('t1'),
          'refresh_token': 'r1',
        }),
      );

      expect(await rig.repository.modules(), TeamModules.none);
      expect(rig.session.signedOut, 0);
      expect(rig.session.keptSignInCleared, 0);
      expect(rig.refreshHost.seen, hasLength(1));
      expect(rig.host.seen, hasLength(2));
    });

    test('an expired token renewed on the way: the modules still arrive',
        () async {
      final rig = _Rig(
        (o) => o.headers['Authorization'] == 'Bearer ${_jwt('t1')}'
            ? _json(200, {
                'features': [
                  {'key': 'tasks', 'dry_run': false}
                ]
              })
            : _json(401, {
                'error': 'Your session has expired. Please sign in again.',
                'code': 'TOKEN_EXPIRED'
              }),
        refresh: (_) => _json(200, {
          'access_token': _jwt('t1'),
          'refresh_token': 'r1',
        }),
      );

      final modules = await rig.repository.modules();

      expect(modules.open, {TeamModule.tasks});
      expect(rig.session.signedOut, 0);
    });

    test('403 for a student token: no modules', () async {
      final rig = _Rig((_) => _json(403, _staffOnly));
      expect(await rig.repository.modules(), TeamModules.none);
      expect(rig.session.signedOut, 0);
      expect(rig.host.seen, hasLength(1));
    });

    // A server without the route: production's /api catch-all, and the
    // closed-module body (middleware/requireFeature.js), the same 404
    // NOT_FOUND either way.
    for (final body in [
      _productionUnknownPath,
      {'error': 'Not found', 'code': 'NOT_FOUND'},
    ]) {
      test('404 "${body['error']}" (no such route yet): no modules',
          () async {
        final rig = _Rig((_) => _json(404, body));
        expect(await rig.repository.modules(), TeamModules.none);
        expect(rig.session.signedOut, 0);
        expect(rig.session.keptSignInCleared, 0);
        expect(rig.host.seen, hasLength(1));
      });
    }

    test('the data source itself reports what failed', () async {
      final notFound = _Rig((_) => _json(404, _productionUnknownPath));
      await expectLater(
          notFound.remote.features(),
          throwsA(
              const NotFoundFailure('API endpoint not found.', 'NOT_FOUND')));

      final student = _Rig((_) => _json(403, _staffOnly));
      await expectLater(student.remote.features(),
          throwsA(const ForbiddenFailure('Access denied. Staff only.')));
    });

    for (final reply in [
      (500, {'error': 'Could not load your features.'}),
      (
        503,
        {
          'error': 'Service temporarily unavailable. Please try again.',
          'code': 'DATABASE_UNAVAILABLE'
        }
      ),
      (502, '<html>Bad gateway</html>'),
    ]) {
      test('${reply.$1}: no modules', () async {
        final rig = _Rig((_) => _json(reply.$1, reply.$2));
        expect(await rig.repository.modules(), TeamModules.none);
        expect(rig.session.signedOut, 0);
        expect(rig.host.seen, hasLength(1));
      });
    }

    test('a timeout: no modules, and it is not retried', () async {
      final rig = _Rig((o) => throw DioException(
          requestOptions: o, type: DioExceptionType.receiveTimeout));
      expect(await rig.repository.modules(), TeamModules.none);
      expect(rig.host.seen, hasLength(1));
      expect(rig.session.signedOut, 0);
    });

    test('a reply that cannot be read: no modules', () async {
      final rig =
          _Rig((_) => ResponseBody.fromString('{not json', 200, headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              }));
      expect(await rig.repository.modules(), TeamModules.none);
    });

    test('offline: no modules, and nothing is sent', () async {
      final rig =
          _Rig((_) => _json(200, {'features': const []}), online: false);
      expect(await rig.repository.modules(), TeamModules.none);
      expect(rig.host.seen, isEmpty);
    });

    test('a connection that never opens: no modules after the usual retries',
        () async {
      final rig = _Rig((o) => throw DioException.connectionError(
          requestOptions: o, reason: 'Connection refused'));
      expect(await rig.repository.modules(), TeamModules.none);
      // RetryInterceptor's three tries for a request that never left, as for
      // every Scheduler call; nothing more.
      expect(rig.host.seen, hasLength(3));
      expect(rig.session.signedOut, 0);
    });
  });

  group('TeamModulesBloc', () {
    final crm = TeamModules({TeamModule.crm: false});
    final crmAndTasks =
        TeamModules({TeamModule.crm: false, TeamModule.tasks: true});

    test('starts with nothing open', () {
      final bloc = TeamModulesBloc(() async => crm);
      expect(bloc.state, const TeamModulesState());
      expect(bloc.state.status, TeamModulesStatus.unknown);
      expect(bloc.state.modules.open, isEmpty);
      bloc.close();
    });

    blocTest<TeamModulesBloc, TeamModulesState>(
      'load: opens what the reply opens',
      build: () => TeamModulesBloc(() async => crm),
      act: (b) => b.add(const TeamModulesLoadRequested()),
      expect: () => [
        const TeamModulesState(status: TeamModulesStatus.loading),
        TeamModulesState(status: TeamModulesStatus.ready, modules: crm),
      ],
    );

    blocTest<TeamModulesBloc, TeamModulesState>(
      'load that throws anyway: nothing open',
      build: () => TeamModulesBloc(() async => throw const ServerFailure()),
      act: (b) => b.add(const TeamModulesLoadRequested()),
      expect: () => const [
        TeamModulesState(status: TeamModulesStatus.loading),
        TeamModulesState(status: TeamModulesStatus.ready),
      ],
    );

    var refreshCalls = 0;
    blocTest<TeamModulesBloc, TeamModulesState>(
      'refresh before any load asks nothing',
      setUp: () => refreshCalls = 0,
      build: () => TeamModulesBloc(() async {
        refreshCalls++;
        return crm;
      }),
      act: (b) => b.add(const TeamModulesRefreshRequested()),
      expect: () => const <TeamModulesState>[],
      verify: (_) => expect(refreshCalls, 0),
    );

    blocTest<TeamModulesBloc, TeamModulesState>(
      'refresh keeps what is open while it asks, then takes the new answer',
      build: () {
        final answers = [crm, crmAndTasks];
        return TeamModulesBloc(() async => answers.removeAt(0));
      },
      act: (b) async {
        b.add(const TeamModulesLoadRequested());
        await Future<void>.delayed(Duration.zero);
        b.add(const TeamModulesRefreshRequested());
      },
      expect: () => [
        const TeamModulesState(status: TeamModulesStatus.loading),
        TeamModulesState(status: TeamModulesStatus.ready, modules: crm),
        TeamModulesState(status: TeamModulesStatus.loading, modules: crm),
        TeamModulesState(status: TeamModulesStatus.ready, modules: crmAndTasks),
      ],
    );

    blocTest<TeamModulesBloc, TeamModulesState>(
      'a refresh that fails closes everything (fail closed)',
      build: () {
        var first = true;
        return TeamModulesBloc(() async {
          if (first) {
            first = false;
            return crm;
          }
          throw const TimeoutFailure();
        });
      },
      act: (b) async {
        b.add(const TeamModulesLoadRequested());
        await Future<void>.delayed(Duration.zero);
        b.add(const TeamModulesRefreshRequested());
      },
      skip: 3,
      expect: () => const [TeamModulesState(status: TeamModulesStatus.ready)],
    );

    var stormCalls = 0;
    blocTest<TeamModulesBloc, TeamModulesState>(
      'one request at a time: asks while one is out are dropped',
      setUp: () => stormCalls = 0,
      build: () => TeamModulesBloc(() async {
        stormCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return crm;
      }),
      act: (b) {
        b
          ..add(const TeamModulesLoadRequested())
          ..add(const TeamModulesLoadRequested())
          ..add(const TeamModulesRefreshRequested())
          ..add(const TeamModulesRefreshRequested());
      },
      wait: const Duration(milliseconds: 60),
      expect: () => [
        const TeamModulesState(status: TeamModulesStatus.loading),
        TeamModulesState(status: TeamModulesStatus.ready, modules: crm),
      ],
      verify: (_) => expect(stormCalls, 1),
    );

    blocTest<TeamModulesBloc, TeamModulesState>(
      'sign-out closes everything',
      build: () => TeamModulesBloc(() async => crm),
      seed: () =>
          TeamModulesState(status: TeamModulesStatus.ready, modules: crm),
      act: (b) => b.add(const TeamModulesCleared()),
      expect: () => const [TeamModulesState()],
    );

    blocTest<TeamModulesBloc, TeamModulesState>(
      'an answer for a signed-out session is dropped; the next sign-in asks '
      'for its own',
      build: () {
        final answers = [
          Completer<TeamModules>(),
          Completer<TeamModules>(),
        ];
        var i = 0;
        final bloc = TeamModulesBloc(() => answers[i++].future);
        Future<void>.delayed(const Duration(milliseconds: 5), () {
          // The new session's answer arrives first, the old one after it.
          answers[1].complete(crmAndTasks);
          answers[0].complete(crm);
        });
        return bloc;
      },
      act: (b) async {
        b.add(const TeamModulesLoadRequested());
        await Future<void>.delayed(Duration.zero);
        b.add(const TeamModulesCleared());
        await Future<void>.delayed(Duration.zero);
        b.add(const TeamModulesLoadRequested());
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        const TeamModulesState(status: TeamModulesStatus.loading),
        const TeamModulesState(),
        const TeamModulesState(status: TeamModulesStatus.loading),
        TeamModulesState(status: TeamModulesStatus.ready, modules: crmAndTasks),
      ],
    );

    blocTest<TeamModulesBloc, TeamModulesState>(
      'refresh after sign-out asks nothing',
      build: () => TeamModulesBloc(() async => crm),
      seed: () =>
          TeamModulesState(status: TeamModulesStatus.ready, modules: crm),
      act: (b) => b
        ..add(const TeamModulesCleared())
        ..add(const TeamModulesRefreshRequested()),
      expect: () => const [TeamModulesState()],
    );
  });
}

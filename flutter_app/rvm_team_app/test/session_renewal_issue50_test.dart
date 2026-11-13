import 'dart:convert';

import 'package:core_auth/core_auth.dart';
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/injection.dart';

/// Answers from [answer] and records the bearer token of every request.
class _Host implements HttpClientAdapter {
  _Host(this.answer);

  final Map<String, Object?> Function(RequestOptions options) answer;
  final List<String?> bearers = [];
  final List<String?> idempotencyKeys = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _,
      Future<void>? __) async {
    bearers.add(options.headers['Authorization'] as String?);
    idempotencyKeys.add(options.headers[IdempotencyInterceptor.header] as String?);
    return ResponseBody.fromString(json.encode(answer(options)), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

String _token(DateTime exp) => 'h.${base64Url.encode(utf8.encode(json.encode({
          'userId': 'u-test',
          'role': 'faculty',
          'exp': exp.millisecondsSinceEpoch ~/ 1000,
        }))).replaceAll('=', '')}.s';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> stored;

  setUp(() {
    // The phone's secure storage, in memory.
    stored = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return stored[key];
        case 'write':
          stored[key!] = args['value'] as String;
          return null;
        case 'delete':
          stored.remove(key);
          return null;
        case 'containsKey':
          return stored.containsKey(key);
        case 'readAll':
          return stored;
        case 'deleteAll':
          stored.clear();
          return null;
      }
      return null;
    });
    getIt.reset();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    getIt.reset();
  });

  test('the Scheduler and ESS clients renew the kept sign-in through one '
      'shared rotator, before the token runs out', () async {
    final spent = _token(DateTime.now().add(const Duration(seconds: 10)));
    final fresh = _token(DateTime.now().add(const Duration(hours: 1)));
    stored
      ..['scheduler_token'] = spent
      ..['ess_refresh_token'] = 'refresh-0'
      ..['ess_install_id'] = 'install-test';
    final session = AuthSession();
    configureDependencies(session);

    // The production rotator talks to the live ESS host; keep its wiring and
    // point only its refresh call at a fake.
    final refresh = _Host((_) => {
          'access_token': fresh,
          'refresh_token': 'refresh-1',
          'access_expires_at':
              DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
        });
    getIt
      ..unregister<SessionRotator>()
      ..registerSingleton<SessionRotator>(SessionRotator(
        tokens: session,
        essTokens: session,
        refreshDio: Dio(BaseOptions(baseUrl: 'https://ess.test/api/ess'))
          ..httpClientAdapter = refresh,
      ));
    final scheduler = _Host((_) => {'ok': true});
    final ess = _Host((_) => {'ok': true});
    getIt<Dio>().httpClientAdapter = scheduler;
    getIt<Dio>(instanceName: 'ess').httpClientAdapter = ess;

    await Future.wait([
      getIt<Dio>().get<dynamic>('/hr/my-attendance/leave'),
      getIt<Dio>().post<dynamic>('/hr/my-attendance/leave',
          data: {'day': '2026-11-20'}),
      getIt<Dio>(instanceName: 'ess').get<dynamic>('/me/capabilities'),
    ]);

    expect(refresh.bearers, hasLength(1), reason: 'one refresh for both');
    expect([...scheduler.bearers, ...ess.bearers],
        everyElement('Bearer $fresh'));
    expect(stored['ess_refresh_token'], 'refresh-1');
    expect(scheduler.idempotencyKeys.whereType<String>(), hasLength(1),
        reason: 'the POST carries a key, the GET does not');
  });
}

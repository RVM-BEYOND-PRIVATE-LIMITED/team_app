import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

final _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

Dio _dio(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://scheduler.test/api'))
    ..httpClientAdapter = adapter;
  dio.interceptors.addAll([
    IdempotencyInterceptor(),
    RetryInterceptor(dio: dio, delays: const [Duration(milliseconds: 1)]),
    const ErrorMappingInterceptor(),
  ]);
  return dio;
}

const _env = ApiEnvironment(
  schedulerBaseUrl: 'https://scheduler.test/api',
  jobPortalBaseUrl: 'https://jobs.test/api/v1',
  essBaseUrl: 'https://ess.test/api/ess',
);

void main() {
  test('every POST, PUT, PATCH and DELETE carries a key; reads carry none',
      () async {
    final adapter = ScriptedAdapter((_) => jsonReply(200, {'ok': true}));
    final dio = _dio(adapter);

    await dio.post<dynamic>('/a', data: {'x': 1});
    await dio.put<dynamic>('/b', data: {'x': 1});
    await dio.patch<dynamic>('/c', data: {'x': 1});
    await dio.delete<dynamic>('/d');
    await dio.get<dynamic>('/e');
    await dio.head<dynamic>('/f');

    final keys = adapter.seen.map((r) => r.idempotencyKey).toList();
    for (final key in keys.take(4)) {
      expect(key, matches(_uuidV4));
    }
    expect(keys.take(4).toSet(), hasLength(4), reason: 'one key per request');
    expect(keys.skip(4), everyElement(isNull));
  });

  test('a retry of the same form sends the same key; a new form a new one',
      () async {
    final adapter = ScriptedAdapter((_) => jsonReply(200, {'ok': true}));
    final dio = _dio(adapter);
    Future<void> submit(String formKey) => dio.post<dynamic>('/leave',
        data: {'day': '2026-11-20'},
        options: Options(extra: {IdempotencyInterceptor.extraKey: formKey}));

    final firstForm = IdempotencyInterceptor.newKey();
    await submit(firstForm);
    await submit(firstForm); // the person taps Retry on the same form
    final secondForm = IdempotencyInterceptor.newKey();
    await submit(secondForm);

    final keys = adapter.seen.map((r) => r.idempotencyKey).toList();
    expect(keys, [firstForm, firstForm, secondForm]);
    expect(firstForm, isNot(secondForm));
  });

  test('a dropped connection replays the same key', () async {
    var calls = 0;
    final adapter = ScriptedAdapter((options) {
      if (++calls < 3) {
        throw DioException(
          requestOptions: options,
          error: const SocketException('Failed host lookup',
              osError: OSError('No address associated with hostname', 7)),
        );
      }
      return jsonReply(201, {'ok': true});
    });

    final res = await _dio(adapter).post<dynamic>('/punch', data: {'x': 1});

    expect(res.statusCode, 201);
    expect(adapter.seen, hasLength(3));
    final keys = adapter.seen.map((r) => r.idempotencyKey).toSet();
    expect(keys, hasLength(1), reason: 'every attempt is the same action');
    expect(keys.single, matches(_uuidV4));
  });

  test('a key the caller set as a header is kept', () async {
    final adapter = ScriptedAdapter((_) => jsonReply(200, {'ok': true}));
    const key = '00000000-0000-4000-8000-000000000001';

    await _dio(adapter).post<dynamic>('/a',
        options: Options(headers: {'idempotency-key': key}));

    expect(adapter.seen.single.idempotencyKey, key);
  });

  test('newKey makes distinct version 4 UUIDs', () {
    final keys = {for (var i = 0; i < 500; i++) IdempotencyInterceptor.newKey()};
    expect(keys, hasLength(500));
    expect(keys, everyElement(matches(_uuidV4)));
  });

  test('every client DioFactory builds adds the interceptor', () {
    final tokens = FakeTokens();
    final clients = [
      DioFactory.scheduler(env: _env, tokens: tokens),
      DioFactory.ess(env: _env, tokens: tokens, essTokens: tokens),
      DioFactory.jobPortal(env: _env, cookieJar: CookieJar()),
    ];
    for (final dio in clients) {
      expect(dio.interceptors.whereType<IdempotencyInterceptor>(), hasLength(1));
    }
  });
}

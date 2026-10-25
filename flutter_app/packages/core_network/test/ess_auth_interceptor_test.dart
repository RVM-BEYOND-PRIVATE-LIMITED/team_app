import 'dart:convert';
import 'dart:typed_data';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// Answers every request with the given status, so a 401 reaches the
/// interceptor without a socket.
class _RefusingAdapter implements HttpClientAdapter {
  _RefusingAdapter(this.status);

  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        '{"error":"Sign in again","code":"NOT_AUTHENTICATED"}',
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

/// Answers with [status]/[body] and remembers the Authorization header it saw.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.status, [this.body = '{}']);

  final int status;
  final String body;
  int calls = 0;
  String? authorization;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    authorization = options.headers['Authorization'] as String?;
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _jwt(Map<String, dynamic> payload) {
  final p =
      base64Url.encode(utf8.encode(json.encode(payload))).replaceAll('=', '');
  return 'header.$p.sig';
}

class _FakeTokens implements TokenStore, EssTokenStore {
  String? schedulerToken = 'stored-token';
  String? refreshToken;
  int unauthorized = 0;

  @override
  Future<String?> readSchedulerToken() async => schedulerToken;

  @override
  Future<void> onUnauthorized() async {
    unauthorized++;
    schedulerToken = null;
  }

  @override
  Future<String?> readEssRefreshToken() async => refreshToken;

  @override
  Future<String> installId() async => 'install-id';

  @override
  Future<void> saveEssSession({
    required String accessToken,
    required String refreshToken,
    DateTime? accessExpiresAt,
  }) async {
    schedulerToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clearEssSession() async {
    refreshToken = null;
  }
}

Dio _dioWith(HttpClientAdapter adapter) => Dio(BaseOptions(
    baseUrl: 'https://ess.test/api/ess',
    validateStatus: (s) => s != null && s < 300))
  ..httpClientAdapter = adapter;

void main() {
  test('an unrecoverable 401 signs the session out', () async {
    final tokens = _FakeTokens();
    final refreshDio = _dioWith(_RefusingAdapter(401));
    final dio = _dioWith(_RefusingAdapter(401))
      ..interceptors.add(EssAuthInterceptor(
          tokens: tokens, essTokens: tokens, refreshDio: refreshDio));

    await expectLater(
        dio.get<dynamic>('/me/capabilities'), throwsA(isA<DioException>()));

    expect(tokens.unauthorized, 1);
  });

  test('a 401 WRONG_PASSWORD reaches the screen and never signs out',
      () async {
    final tokens = _FakeTokens();
    final refreshAdapter = _RecordingAdapter(
        200, '{"access_token":"fresh-token","refresh_token":"next-refresh"}');
    final apiAdapter = _RecordingAdapter(
        401, '{"error":"Wrong password.","code":"WRONG_PASSWORD"}');
    final dio = _dioWith(apiAdapter)
      ..interceptors.add(EssAuthInterceptor(
        tokens: tokens,
        essTokens: tokens,
        refreshDio: _dioWith(refreshAdapter),
      ));

    await expectLater(
        dio.post<dynamic>('/me/password'), throwsA(isA<DioException>()));

    expect(tokens.unauthorized, 0, reason: 'a wrong password is not a session');
    expect(refreshAdapter.calls, 0, reason: 'no rotation for a refusal');
    expect(apiAdapter.calls, 1, reason: 'not replayed');
  });

  test('a 401 on the kept-sign-in exchange never signs out', () async {
    final tokens = _FakeTokens();
    final refreshDio = _dioWith(_RefusingAdapter(401));
    final dio = _dioWith(_RefusingAdapter(401))
      ..interceptors.add(EssAuthInterceptor(
          tokens: tokens, essTokens: tokens, refreshDio: refreshDio));

    await expectLater(
        dio.post<dynamic>('/session'), throwsA(isA<DioException>()));

    expect(tokens.unauthorized, 0);
  });

  test('a spent token is rotated before the request leaves, not after a 401',
      () async {
    final tokens = _FakeTokens()
      ..schedulerToken = _jwt({
        'exp': DateTime.now()
                .subtract(const Duration(minutes: 1))
                .millisecondsSinceEpoch ~/
            1000,
      })
      ..refreshToken = 'refresh-token';
    final refreshAdapter = _RecordingAdapter(
      200,
      '{"access_token":"fresh-token","refresh_token":"next-refresh"}',
    );
    final apiAdapter = _RecordingAdapter(200);
    final dio = _dioWith(apiAdapter)
      ..interceptors.add(EssAuthInterceptor(
        tokens: tokens,
        essTokens: tokens,
        refreshDio: _dioWith(refreshAdapter),
      ));

    await dio.get<dynamic>('/me/capabilities');

    expect(refreshAdapter.calls, 1, reason: 'refreshes before the call');
    expect(apiAdapter.calls, 1);
    expect(apiAdapter.authorization, 'Bearer fresh-token');
    expect(tokens.schedulerToken, 'fresh-token');
    expect(tokens.refreshToken, 'next-refresh');
    expect(tokens.unauthorized, 0, reason: 'no 401 ever reaches dio');
  });

  test('a live token is sent as-is, with no refresh', () async {
    final tokens = _FakeTokens()
      ..schedulerToken = _jwt({
        'exp': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      })
      ..refreshToken = 'refresh-token';
    final refreshAdapter = _RecordingAdapter(500);
    final apiAdapter = _RecordingAdapter(200);
    final dio = _dioWith(apiAdapter)
      ..interceptors.add(EssAuthInterceptor(
        tokens: tokens,
        essTokens: tokens,
        refreshDio: _dioWith(refreshAdapter),
      ));

    await dio.get<dynamic>('/me/capabilities');

    expect(refreshAdapter.calls, 0);
    expect(apiAdapter.authorization, 'Bearer ${tokens.schedulerToken}');
  });
}

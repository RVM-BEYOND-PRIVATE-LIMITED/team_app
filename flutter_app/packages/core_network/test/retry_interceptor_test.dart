import 'dart:io';
import 'dart:typed_data';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// Fails the first [failures] calls with a DNS lookup failure, then answers 200.
class _FlakyAdapter implements HttpClientAdapter {
  _FlakyAdapter({this.failures = 0, this.status = 200, this.body = '{"ok":true}'});

  final int failures;
  final int status;
  final String body;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    calls++;
    if (calls <= failures) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        error: const SocketException("Failed host lookup: 'team-api.rvmcad.org'",
            osError: OSError('No address associated with hostname', 7)),
      );
    }
    return ResponseBody.fromString(body, status,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

/// Answers every call with a fixed non-2xx status.
class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);
  final int status;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    calls++;
    return ResponseBody.fromString('{"error":"nope"}', status,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(HttpClientAdapter adapter, {int maxAttempts = 3}) {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://team-api.rvmcad.org/api/ess',
    validateStatus: (s) => s != null && s >= 200 && s < 300,
  ))
    ..httpClientAdapter = adapter;
  dio.interceptors.addAll([
    RetryInterceptor(dio: dio, maxAttempts: maxAttempts, delays: const [Duration(milliseconds: 1)]),
    const ErrorMappingInterceptor(),
  ]);
  return dio;
}

void main() {
  test('retries a DNS/connection failure, then succeeds', () async {
    final adapter = _FlakyAdapter(failures: 2);
    final res = await _dio(adapter).get('/health');
    expect(res.statusCode, 200);
    expect(adapter.calls, 3);
  });

  test('gives up after maxAttempts and surfaces the failure', () async {
    final adapter = _FlakyAdapter(failures: 99);
    await expectLater(_dio(adapter, maxAttempts: 3).get('/health'), throwsA(isA<DioException>()));
    expect(adapter.calls, 3);
  });

  test('does not retry a real HTTP error', () async {
    final adapter = _StatusAdapter(400);
    await expectLater(_dio(adapter).get('/health'), throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
  });

  test('does not retry a non-replayable body', () async {
    final adapter = _FlakyAdapter(failures: 99);
    final and = _dio(adapter);
    final form = FormData.fromMap({'a': 'b'});
    await expectLater(and.post('/upload', data: form), throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
  });
}

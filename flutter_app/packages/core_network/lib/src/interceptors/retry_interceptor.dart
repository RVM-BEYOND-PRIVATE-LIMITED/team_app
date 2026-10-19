import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../failure.dart';

/// Retries a request whose connection never reached the server: a DNS lookup
/// failure (`Failed host lookup` / `No address associated with hostname`), a
/// refused connection, or an unreachable host.
///
/// The common case is the app's FIRST call on a cold start — right after a fresh
/// install or a network handover the OS resolver is not ready yet and the very
/// next attempt succeeds. Because a connection that never opened proves the
/// request was not delivered, retrying is safe for every method, POST included.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required Dio dio,
    this.maxAttempts = 3,
    this.delays = const [Duration(milliseconds: 400), Duration(seconds: 1)],
  }) : _dio = dio;

  final Dio _dio;

  /// Total tries, the original included.
  final int maxAttempts;

  /// Wait before each retry; the last delay repeats if attempts outnumber it.
  final List<Duration> delays;

  static const _attemptKey = 'rvm.retry.attempt';

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 0;
    if (attempt + 1 >= maxAttempts || !_isRetryable(err, err.requestOptions)) {
      handler.next(err);
      return;
    }
    final delay = delays[attempt < delays.length ? attempt : delays.length - 1];
    await Future<void>.delayed(delay);
    final options = err.requestOptions..extra[_attemptKey] = attempt + 1;
    try {
      handler.resolve(await _dio.fetch(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Only failures that prove the request was never delivered, and only for
  /// replayable bodies (a stream/FormData may already be consumed).
  static bool _isRetryable(DioException err, RequestOptions options) {
    if (!_isReplayable(options.data)) return false;
    if (err.type == DioExceptionType.connectionError) return true;
    final e = err.error;
    // ErrorMappingInterceptor may have run already and swapped in a Failure.
    if (e is NoConnectionFailure) return true;
    if (e is SocketException) {
      final message = e.message.toLowerCase();
      if (message.contains('host lookup') || message.contains('name or service')) return true;
      // EAI_AGAIN (6), EAI_NONAME/ENOTFOUND (7/8), ENETUNREACH (101),
      // ECONNREFUSED (111), EHOSTUNREACH (113): the connection never opened.
      return const {6, 7, 8, 101, 111, 113}.contains(e.osError?.errorCode);
    }
    return false;
  }

  static bool _isReplayable(Object? data) =>
      data == null || data is Map || data is List || data is String || data is num || data is bool;
}

// Every line is printed to stdout (`print`) so it ALWAYS lands in the IDE
// "Debug Console" as plain, selectable/copyable text. developer.log output can
// be filtered or rerouted by some IDE setups (which is why error lines went
// missing). This interceptor is registered in DEBUG builds only (see
// DioFactory), so none of these prints ship to release.
// ignore_for_file: avoid_print

import 'package:dio/dio.dart';

/// Lightweight request/response/error logger (method · URL · status · duration
/// · real cause). Success bodies are NOT logged — avoids leaking tokens/PII,
/// keeping a clean Play data-safety posture. Error envelopes
/// (`{error:{code,message}}`) carry no secrets, so their cause IS logged.
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor();

  static const _key = 'rvm_start';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_key] = DateTime.now().millisecondsSinceEpoch;
    print('[rvm.net] → ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    print('[rvm.net] ← ${response.statusCode} ${response.requestOptions.uri} '
        '${_ms(response.requestOptions)}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode ?? err.type.name;
    final cause = _serverError(err.response?.data) ?? err.error?.toString() ?? '';
    print('[rvm.net] ✗ $status ${err.requestOptions.method} ${err.requestOptions.uri} '
        '${_ms(err.requestOptions)} (${err.type.name})'
        '${cause.isEmpty ? '' : ' — $cause'}');
    handler.next(err);
  }

  /// Pull the backend error envelope `{error:{code,message}}` / `{message}` for
  /// diagnostics. Error bodies carry the real cause and no tokens/PII, so —
  /// unlike success payloads — they are safe to log.
  String? _serverError(dynamic data) {
    if (data is Map) {
      final err = data['error'];
      if (err is Map) {
        final parts = [err['code'], err['message']].where((v) => v != null).map((v) => v.toString());
        if (parts.isNotEmpty) return parts.join(': ');
      }
      final m = data['message'] ?? data['error'];
      if (m != null) return m.toString();
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }

  String _ms(RequestOptions o) {
    final start = o.extra[_key];
    if (start is! int) return '';
    return '(${DateTime.now().millisecondsSinceEpoch - start}ms)';
  }
}

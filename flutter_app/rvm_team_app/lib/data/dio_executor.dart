import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

/// Wraps a raw dio call so every data source throws the shared typed [Failure]
/// instead of a DioException — the same convention as the shared `data` package.
///
/// A 5xx response is deliberately not thrown by the ESS client (see
/// `configureDependencies`): it comes back as a normal [Response] so the debugger
/// does not stop on a handled server error. This mixin turns that response into
/// the same typed [Failure] the rest of the app already understands.
mixin DioExecutor {
  Future<T> guard<T>(Future<T> Function() run) async {
    try {
      final value = await run();
      if (value is Response) {
        final status = value.statusCode ?? 0;
        if (status < 200 || status >= 300) {
          throw failureFromResponse(status, value.data);
        }
      }
      return value;
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }
}

/// Maps a non-2xx [Response] body to the typed [Failure], keeping the ESS's
/// staff-readable 503 copy (`MODULE_NOT_INSTALLED` / `UNAVAILABLE`).
Failure failureFromResponse(int status, dynamic data) {
  String? message;
  String? code;
  if (data is Map) {
    final error = data['error'];
    if (error is Map) {
      message = error['message']?.toString();
      code = error['code']?.toString();
    } else if (error is String) {
      // The ESS writes `{error: "the staff-readable reason", code: "..."}`.
      message = error;
    }
    message ??= data['message']?.toString();
    code ??= data['code']?.toString();
  }
  return Failure.fromStatus(status, message, code);
}

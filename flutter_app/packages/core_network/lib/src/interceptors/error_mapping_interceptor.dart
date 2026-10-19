import 'package:dio/dio.dart';

import '../failure.dart';

/// Converts every raw [DioException] into a typed [Failure] and attaches it to
/// the rejected error, so data sources rethrow the real cause (timeout / 401 /
/// 5xx / no-connection / parse) instead of an opaque dio error.
class ErrorMappingInterceptor extends Interceptor {
  const ErrorMappingInterceptor();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final failure = err.error is Failure ? err.error as Failure : Failure.fromDio(err);
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: failure,
        stackTrace: err.stackTrace,
      ),
    );
  }
}

extension DioFailure on DioException {
  /// The typed failure attached by [ErrorMappingInterceptor], or a best-effort map.
  Failure get asFailure => error is Failure ? error as Failure : Failure.fromDio(this);
}

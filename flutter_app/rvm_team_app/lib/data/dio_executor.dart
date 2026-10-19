import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

/// Wraps a raw dio call so every data source throws the shared typed [Failure]
/// instead of a DioException — the same convention as the shared `data` package.
mixin DioExecutor {
  Future<T> guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw Failure.fromDio(e);
    }
  }
}

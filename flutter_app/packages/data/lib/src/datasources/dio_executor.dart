import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

/// Runs a dio call and rethrows the typed [Failure] the ErrorMappingInterceptor
/// attached (or maps it if missing). Keeps every data source one-liner-clean.
mixin DioExecutor {
  Future<T> guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw e.asFailure;
    }
  }

  Map<String, dynamic> asMap(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
}

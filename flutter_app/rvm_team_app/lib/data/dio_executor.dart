import 'dart:io';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../app_crash.dart';

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
          CrashReporter.note('last_api',
              '${CrashReporter.apiLine(value.requestOptions.method, value.requestOptions.path)} -> $status');
          throw failureFromResponse(status, value.data);
        }
      }
      return value;
    } on DioException catch (e) {
      CrashReporter.note('last_api',
          '${CrashReporter.apiLine(e.requestOptions.method, e.requestOptions.path)} -> ${e.response?.statusCode ?? e.type.name}');
      throw Failure.fromDio(e);
    } on SocketException catch (e) {
      // A DNS/connectivity error that reached us outside a DioException
      // (custom connection factory, platform channel). Staff read this, not
      // the raw `SocketException: Failed host lookup …` text.
      debugPrint('Connectivity failure: $e');
      throw const NoConnectionFailure();
    } catch (e, stack) {
      // A parse error or a plugin failure is still one failed request: make it
      // a typed Failure so every bloc's `on Failure` handler resets its loading
      // state and shows a message instead of leaving a spinner forever.
      if (e is Failure) rethrow;
      debugPrint('Unexpected request failure: $e\n$stack');
      throw const UnknownFailure('Could not read the server response.');
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

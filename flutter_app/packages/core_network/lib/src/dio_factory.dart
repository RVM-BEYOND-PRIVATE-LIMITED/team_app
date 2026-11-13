import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'api_environment.dart';
import 'doh_http_client_adapter.dart';
import 'ess_token_store.dart';
import 'interceptors/bearer_auth_interceptor.dart';
import 'interceptors/envelope_interceptor.dart';
import 'interceptors/error_mapping_interceptor.dart';
import 'interceptors/ess_auth_interceptor.dart';
import 'interceptors/idempotency_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'session_rotator.dart';
import 'token_store.dart';

/// One centralized place that builds the two configured [Dio] instances the app
/// runs on. Both share the same base options + logging + typed-error mapping;
/// they differ only in auth (Scheduler bearer header vs JobPortal session
/// cookie + `{success,data}` envelope). Registered in get_it once at startup.
abstract final class DioFactory {
  static const _timeout = Duration(seconds: 30);

  /// A native-clock User-Agent. The Scheduler's punch path (task B13) refuses
  /// anything that is not a mobile client, so every app call carries it.
  static const userAgent = 'RVM-Team/0.1.0 (Android)';

  static BaseOptions _base(String baseUrl) => BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
        sendTimeout: _timeout,
        contentType: 'application/json',
        // Let dio return non-2xx to the error path so typed failures fire.
        validateStatus: (s) => s != null && s >= 200 && s < 300,
      );

  /// Scheduler (Express) — `Authorization: Bearer <jwt>` header.
  ///
  /// [cookieJar], when given, persists the punch device cookie (`rvm_att_dev`)
  /// across launches (tasks B8/B13); without it the cookie is dropped after the
  /// first punch and every later punch is refused.
  ///
  /// [sessions], when given, renews the kept sign-in's access token for this
  /// client too (team_app #50). Pass the same [SessionRotator] to [ess].
  static Dio scheduler({
    required ApiEnvironment env,
    required TokenStore tokens,
    CookieJar? cookieJar,
    SessionRotator? sessions,
    bool logging = false,
  }) {
    final dio = Dio(_base(env.schedulerBaseUrl));
    dio.httpClientAdapter = DohHttpClientAdapter.create();
    dio.options.headers['User-Agent'] = userAgent;
    dio.interceptors.addAll([
      IdempotencyInterceptor(),
      RetryInterceptor(dio: dio),
      if (cookieJar != null) CookieManager(cookieJar),
      BearerAuthInterceptor(tokens, sessions: sessions, dio: dio),
      if (logging) LoggingInterceptor(),
      const ErrorMappingInterceptor(),
    ]);
    return dio;
  }

  /// Team RVM ESS (Express, `/api/ess`) — bearer token, with a kept sign-in that
  /// rotates the refresh token on a rejected access token (task A3).
  ///
  /// [sessions] is the renewal shared with the Scheduler client; without it
  /// this client renews on its own.
  static Dio ess({
    required ApiEnvironment env,
    required TokenStore tokens,
    required EssTokenStore essTokens,
    SessionRotator? sessions,
    bool logging = false,
  }) {
    final refreshDio = Dio(_base(env.essBaseUrl));
    final dio = Dio(_base(env.essBaseUrl));
    refreshDio.httpClientAdapter = DohHttpClientAdapter.create();
    dio.httpClientAdapter = DohHttpClientAdapter.create();
    dio.options.headers['User-Agent'] = userAgent;
    dio.interceptors.addAll([
      IdempotencyInterceptor(),
      RetryInterceptor(dio: dio),
      EssAuthInterceptor(
        tokens: tokens,
        essTokens: essTokens,
        refreshDio: refreshDio,
        sessions: sessions,
      ),
      if (logging) LoggingInterceptor(),
      const ErrorMappingInterceptor(),
    ]);
    return dio;
  }

  /// The kept sign-in's renewal, built once and passed to both [scheduler] and
  /// [ess] so the two clients renew the shared access token in one flight. Its
  /// refresh call goes through a bare client on the ESS host.
  static SessionRotator sessionRotator({
    required ApiEnvironment env,
    required TokenStore tokens,
    required EssTokenStore essTokens,
  }) {
    final refreshDio = Dio(_base(env.essBaseUrl))
      ..httpClientAdapter = DohHttpClientAdapter.create();
    return SessionRotator(
      tokens: tokens,
      essTokens: essTokens,
      refreshDio: refreshDio,
    );
  }

  /// JobPortal (Next.js) — `rvm_session` cookie + `{success,data}` envelope.
  static Dio jobPortal({
    required ApiEnvironment env,
    required CookieJar cookieJar,
    bool logging = false,
  }) {
    final dio = Dio(_base(env.jobPortalBaseUrl));
    dio.httpClientAdapter = DohHttpClientAdapter.create();
    dio.interceptors.addAll([
      IdempotencyInterceptor(),
      RetryInterceptor(dio: dio),
      CookieManager(cookieJar),
      const EnvelopeInterceptor(),
      if (logging) LoggingInterceptor(),
      const ErrorMappingInterceptor(),
    ]);
    return dio;
  }
}

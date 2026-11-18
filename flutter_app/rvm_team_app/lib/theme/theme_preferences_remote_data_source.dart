import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

import '../data/dio_executor.dart';
import 'theme_preference.dart';

/// Scheduler theme preference: `GET/PUT /me/preferences`.
///
/// The Scheduler client's base URL already ends in `/api`, so the path is
/// `/me/preferences`. PUT carries a new Idempotency-Key per save (the
/// Scheduler replays the first answer for a repeated key).
class ThemePreferencesRemoteDataSource with DioExecutor {
  ThemePreferencesRemoteDataSource(this._dio);

  final Dio _dio;

  Future<ThemePreference> getPreference() => guard(() async {
        final res = await _dio.get('/me/preferences');
        return ThemePreference.fromJson(
            (res.data as Map).cast<String, dynamic>());
      });

  Future<ThemePreference> savePreference(
    ThemeChoice choice, {
    String? idempotencyKey,
  }) =>
      guard(() async {
        final res = await _dio.put(
          '/me/preferences',
          data: {'theme': choice.wire},
          options: Options(extra: {
            IdempotencyInterceptor.extraKey:
                idempotencyKey ?? IdempotencyInterceptor.newKey(),
          }),
        );
        return ThemePreference.fromJson(
            (res.data as Map).cast<String, dynamic>());
      });
}

import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler recent-activity feed over the Bearer-JWT Dio (newest 10, auto-scoped
/// to the caller's branch; super-admin may pass [locationId]).
class ActivitiesRemoteDataSource with DioExecutor {
  ActivitiesRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<Activity>> list({String? locationId}) =>
      guard(() async => Parse.activities((await _dio.get('/activities', queryParameters: {
            if (locationId != null) 'location_id': locationId,
          }))
              .data));
}

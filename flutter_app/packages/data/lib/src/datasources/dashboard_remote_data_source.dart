import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Staff dashboard over the Scheduler Dio (Bearer JWT). Backend scopes the
/// numbers to the caller's branch / global role.
class DashboardRemoteDataSource with DioExecutor {
  DashboardRemoteDataSource(this._dio);

  final Dio _dio;

  Future<DashboardMetrics> metrics() =>
      guard(() async => Parse.dashboardMetrics((await _dio.get('/dashboard')).data));

  Future<int> yesterdayAttendance() => guard(
      () async => Parse.yesterdayAttendance((await _dio.get('/dashboard/yesterday-attendance')).data));
}

import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Student training flows over the Scheduler Dio (announcements, batches).
class SchedulerRemoteDataSource with DioExecutor {
  SchedulerRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<AnnouncementItem>> announcements() =>
      guard(() async => Parse.announcements((await _dio.get('/announcements')).data));

  Future<List<BatchSummary>> studentBatches(String studentId) =>
      guard(() async => Parse.batches((await _dio.get('/students/$studentId/batches')).data));
}

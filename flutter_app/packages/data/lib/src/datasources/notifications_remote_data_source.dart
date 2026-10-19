import 'package:dio/dio.dart';

import 'dio_executor.dart';

/// Candidate notifications over the JobPortal Dio.
class NotificationsRemoteDataSource with DioExecutor {
  NotificationsRemoteDataSource(this._dio);

  final Dio _dio;

  Future<int> unreadCount() => guard(() async {
        final data = asMap((await _dio.get('/notifications/unread-count')).data);
        final c = data['count'];
        return c is int ? c : (c is num ? c.toInt() : int.tryParse('$c') ?? 0);
      });
}

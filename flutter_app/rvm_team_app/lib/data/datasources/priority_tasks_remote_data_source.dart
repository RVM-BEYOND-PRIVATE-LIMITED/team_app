import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../dio_executor.dart';

/// Priority tasks set by the CEO / HoO / super admin for the branches.
///   GET   /api/priority-tasks/inbox
///   PATCH /api/priority-tasks/:id          (status, progress_note)
///   PATCH /api/priority-tasks/:id/cancel   (reason)
///   POST  /api/priority-tasks/:id/ack
class PriorityTasksRemoteDataSource with DioExecutor {
  PriorityTasksRemoteDataSource(this._dio);

  final Dio _dio;

  Future<PriorityInbox> inbox() => guard(() async {
        final res = await _dio.get('/priority-tasks/inbox');
        return PriorityInbox.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<PriorityTask> update(String id, {String? status, String? progressNote}) => guard(() async {
        final res = await _dio.patch('/priority-tasks/$id', data: {
          if (status != null) 'status': status,
          if (progressNote != null) 'progress_note': progressNote,
        });
        return PriorityTask.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<PriorityTask> cancel(String id, String reason) => guard(() async {
        final res = await _dio.patch('/priority-tasks/$id/cancel', data: {'reason': reason});
        return PriorityTask.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<void> acknowledge(String id) => guard(() => _dio.post('/priority-tasks/$id/ack'));
}

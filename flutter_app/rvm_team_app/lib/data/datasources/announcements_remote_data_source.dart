import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../dio_executor.dart';

/// Branch announcements (`GET /api/announcements`) — the closest existing
/// content to the app's Home announcements.
class AnnouncementsRemoteDataSource with DioExecutor {
  AnnouncementsRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<TeamAnnouncement>> list() => guard(() async {
        final res = await _dio.get('/announcements');
        final list = (res.data as List?) ?? const [];
        return list
            .whereType<Map>()
            .map((e) => TeamAnnouncement.fromJson(e.cast<String, dynamic>()))
            .toList();
      });
}

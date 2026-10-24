import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../dio_executor.dart';

/// Branch announcements (`GET /api/announcements`) — the closest existing
/// content to the app's Home announcements.
class AnnouncementsRemoteDataSource with DioExecutor {
  AnnouncementsRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<TeamAnnouncement>> list() async {
    try {
      final res = await _dio.get('/announcements',
          options: Options(validateStatus: (_) => true));
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return const [];
      final list = (res.data as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => TeamAnnouncement.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      // Home announcements are an optional card; a refused/offline read must
      // show the empty state, not a thrown exception.
      return const [];
    }
  }
}

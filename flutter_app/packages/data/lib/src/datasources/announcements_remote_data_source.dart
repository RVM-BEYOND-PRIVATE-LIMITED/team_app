import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler announcements over the Bearer-JWT Dio, staff side (compose +
/// delete). Reads auto-scope to the caller's branch (super-admin may pass
/// [locationId] to focus a city); CREATE is branch-scoped server-side — it uses
/// the caller's `locationId`, so a super-admin without a location gets a 401.
class AnnouncementsRemoteDataSource with DioExecutor {
  AnnouncementsRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /announcements → `[{..., batch:{name}}]`, newest first.
  Future<List<AnnouncementItem>> list({String? locationId}) =>
      guard(() async => Parse.announcements((await _dio.get('/announcements', queryParameters: {
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// POST /announcements — returns the created row (with batch name joined).
  Future<AnnouncementItem> create(AnnouncementDraft draft) => guard(
      () async => Parse.announcementOf((await _dio.post('/announcements', data: draft.toJson())).data));

  /// DELETE /announcements/:id — 204 No Content.
  Future<void> delete(String id) => guard(() async {
        await _dio.delete('/announcements/$id');
      });
}

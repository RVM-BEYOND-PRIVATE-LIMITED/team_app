import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler pending-alerts over the Bearer-JWT Dio. Reads auto-scope to the
/// caller's branch (super-admin may pass [locationId]); resolve is location-
/// checked server-side (403 for another branch's alert).
class AlertsRemoteDataSource with DioExecutor {
  AlertsRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /alerts/pending — unresolved alerts for the branch (server auto-resolves
  /// stale ones as a side effect).
  Future<List<PendingAlert>> pending({String? locationId, String? alertType}) =>
      guard(() async => Parse.pendingAlerts((await _dio.get('/alerts/pending', queryParameters: {
            if (locationId != null) 'location_id': locationId,
            if (alertType != null) 'alert_type': alertType,
          }))
              .data));

  /// POST /alerts/:id/resolve — resolve a single alert.
  Future<void> resolve(String id) => guard(() async {
        await _dio.post('/alerts/$id/resolve');
      });

  /// POST /alerts/bulk-resolve — resolve every alert for a date (+ type) in the
  /// caller's branch.
  Future<void> bulkResolve({required String date, String? alertType}) => guard(() async {
        await _dio.post('/alerts/bulk-resolve', data: {
          'date': date,
          if (alertType != null) 'alert_type': alertType,
        });
      });
}

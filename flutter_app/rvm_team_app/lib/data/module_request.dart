import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

import '../router/module_routes.dart';

/// A module's own API requests carry their module (team_app #50, item 12), so
/// a 404 `NOT_FOUND` from a closed switch becomes a [ModuleUnavailableFailure]
/// that `BlockedState` shows as "module off" (`blockedReasonFor`). A request
/// without it keeps today's [NotFoundFailure].
///
/// In a data source (`with DioExecutor`):
///
/// ```dart
/// Future<Leads> leads() => guard(() async => Leads.fromJson(bodyOf(
///     await _dio.get('/crm/leads', options: TeamModule.crm.requestOptions))));
/// ```
extension TeamModuleRequest on TeamModule {
  /// Options for a request to this module's API.
  Options get requestOptions => Options(extra: ModuleRequest.extra(key));
}

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

import '../../domain/team_modules.dart';
import '../dio_executor.dart';

/// The staff modules open to the signed-in person (team_app #50, item 5).
///
/// Endpoint (Scheduler client, staff only):
///   GET /api/me/features → 200 `{ features: [{ key, dry_run }] }`
///
/// Its 401 never ends the session ([BearerAuthInterceptor.keepSessionKey]):
/// the list is optional, and a server that refuses it (a student token 403, a
/// server without the route 404, a sign-in in flight with no token yet 401)
/// means "no modules", never "sign in again".
class TeamModulesRemoteDataSource with DioExecutor {
  TeamModulesRemoteDataSource(this._dio);

  final Dio _dio;

  /// The path under the Scheduler client's `/api` base.
  static const path = '/me/features';

  /// The open modules. Throws the typed [Failure] of a refused or failed
  /// request; a 200 body of the wrong shape opens nothing.
  Future<TeamModules> features() => guard(() async {
        final res = await _dio.get<Object?>(
          path,
          options: Options(extra: {BearerAuthInterceptor.keepSessionKey: true}),
        );
        return TeamModules.fromJson(bodyOf(res));
      });
}

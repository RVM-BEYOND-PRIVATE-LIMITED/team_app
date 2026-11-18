import 'package:dio/dio.dart';

/// Marks a request as one of a staff module's own API calls (team_app #50,
/// item 12), so its 404 `NOT_FOUND` reads as "this module is not open to
/// you" ([Failure.forModule]) instead of "no data found".
///
/// A Scheduler module route behind a closed feature switch answers 404
/// `{ error: 'Not found', code: 'NOT_FOUND' }` (Scheduler_Backend
/// middleware/requireFeature.js), the same body for "switched off" and "not
/// in the pilot", and the same code an unknown path gets, so a module that is
/// not deployed yet reads the same way. Only a request that carries the tag
/// is read like this; a 404 `NOT_FOUND` anywhere else stays a
/// [NotFoundFailure], as before.
abstract final class ModuleRequest {
  /// The request `extra` key that names the module.
  static const extraKey = 'rvm.module';

  /// The `extra` of a request to [module]'s API, e.g. `crm`.
  static Map<String, Object?> extra(String module) => {extraKey: module};

  /// The module [options] was sent for, or null for any other request.
  static String? of(RequestOptions options) {
    final module = options.extra[extraKey];
    return module is String && module.isNotEmpty ? module : null;
  }
}

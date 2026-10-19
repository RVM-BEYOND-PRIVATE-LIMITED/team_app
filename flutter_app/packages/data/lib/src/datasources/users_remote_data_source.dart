import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler user-provisioning over the Bearer-JWT Dio (super-admin console).
/// The reads/writes are location-scoped server-side; reset-password is a public
/// forgot-password flow (verified by username + phone).
class UsersRemoteDataSource with DioExecutor {
  UsersRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /users — all users (super) or the branch's users (admin).
  Future<List<StaffUser>> list({String? locationId}) =>
      guard(() async => Parse.staffUsers((await _dio.get('/users', queryParameters: {
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// GET /users/admins — the admin accounts (for assignment pickers).
  Future<List<StaffUser>> admins({String? locationId}) =>
      guard(() async => Parse.staffUsers((await _dio.get('/users/admins', queryParameters: {
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// POST /users/super-provision — create a user at any branch/role (super only).
  Future<StaffUser> provision(UserProvisionDraft draft) => guard(
      () async => Parse.staffUserOf((await _dio.post('/users/super-provision', data: draft.toJson())).data));

  /// PATCH /users/update/:id — update profile / role / password.
  Future<StaffUser> update(String id, UserUpdate update) => guard(
      () async => Parse.staffUserOf((await _dio.patch('/users/update/$id', data: update.toJson())).data));

  /// PATCH /users/assign-role — change a user's role.
  Future<void> assignRole({required String userId, required String role}) => guard(() async {
        await _dio.patch('/users/assign-role', data: {'userId': userId, 'role': role});
      });

  /// DELETE /users/:id — full purge of the user + related assets.
  Future<void> delete(String id) => guard(() async {
        await _dio.delete('/users/$id');
      });

  /// POST /users/reset-password — public forgot-password.
  Future<void> resetPassword(ResetPasswordDraft draft) => guard(() async {
        await _dio.post('/users/reset-password', data: draft.toJson());
      });
}

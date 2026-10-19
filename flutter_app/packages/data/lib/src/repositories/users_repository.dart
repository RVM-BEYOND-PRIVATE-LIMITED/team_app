import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/users_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff user-provisioning (Scheduler, super-admin console). Connectivity-guarded
/// pass-throughs — list/admins reads, provision/update/assign-role/delete writes,
/// and the public reset-password.
class UsersRepository with ConnectivityGuard {
  UsersRepository({required UsersRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final UsersRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<StaffUser>> list({String? locationId}) async {
    await ensureOnline();
    return _remote.list(locationId: locationId);
  }

  Future<List<StaffUser>> admins({String? locationId}) async {
    await ensureOnline();
    return _remote.admins(locationId: locationId);
  }

  Future<StaffUser> provision(UserProvisionDraft draft) async {
    await ensureOnline();
    return _remote.provision(draft);
  }

  Future<StaffUser> update(String id, UserUpdate update) async {
    await ensureOnline();
    return _remote.update(id, update);
  }

  Future<void> assignRole({required String userId, required String role}) async {
    await ensureOnline();
    return _remote.assignRole(userId: userId, role: role);
  }

  Future<void> delete(String id) async {
    await ensureOnline();
    return _remote.delete(id);
  }

  Future<void> resetPassword(ResetPasswordDraft draft) async {
    await ensureOnline();
    return _remote.resetPassword(draft);
  }
}

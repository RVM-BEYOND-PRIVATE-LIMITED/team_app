import 'package:core_network/core_network.dart';

import '../connectivity_guard.dart';
import '../datasources/me_remote_data_source.dart';
import '../../domain/models.dart';

/// The caller's own account + security actions.
class MeRepository with ConnectivityGuard {
  MeRepository({required MeRemoteDataSource remote, required this.connectivity}) : _remote = remote;

  final MeRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<TeamProfile> me() async {
    await ensureOnline();
    return _remote.me();
  }

  Future<List<SecurityEvent>> securityEvents() async {
    await ensureOnline();
    return _remote.securityEvents();
  }

  Future<TeamProfile> uploadPhoto(List<int> bytes, String filename) async {
    await ensureOnline();
    return _remote.uploadPhoto(bytes, filename);
  }

  Future<TeamProfile> removePhoto() async {
    await ensureOnline();
    return _remote.removePhoto();
  }

  Future<String?> requestEmailChange({required String email, required String password}) async {
    await ensureOnline();
    return _remote.requestEmailChange(email: email, password: password);
  }

  Future<TeamProfile> confirmEmailChange(String code) async {
    await ensureOnline();
    return _remote.confirmEmailChange(code);
  }

  Future<String?> requestPhoneChange({required String phoneNumber, required String password}) async {
    await ensureOnline();
    return _remote.requestPhoneChange(phoneNumber: phoneNumber, password: password);
  }

  Future<TeamProfile> confirmPhoneChange(String code) async {
    await ensureOnline();
    return _remote.confirmPhoneChange(code);
  }

  Future<void> requestTwoFactorEnable() async {
    await ensureOnline();
    return _remote.requestTwoFactorEnable();
  }

  Future<TeamProfile> enableTwoFactor(String code) async {
    await ensureOnline();
    return _remote.enableTwoFactor(code);
  }

  Future<TeamProfile> disableTwoFactor(String password) async {
    await ensureOnline();
    return _remote.disableTwoFactor(password);
  }

  Future<void> changePassword({required String oldPassword, required String newPassword}) async {
    await ensureOnline();
    return _remote.changePassword(oldPassword: oldPassword, newPassword: newPassword);
  }
}

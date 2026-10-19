import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../dio_executor.dart';

/// The caller's own account and security settings (`/api/me/*`).
///
/// Endpoints:
///   GET    /api/me
///   GET    /api/me/security-events
///   POST   /api/me/photo            (multipart, field `photo`)
///   DELETE /api/me/photo
///   POST   /api/me/email/request    /api/me/email/confirm
///   POST   /api/me/phone/request    /api/me/phone/confirm
///   POST   /api/me/two-factor/request|enable|disable
///   POST   /api/me/password
class MeRemoteDataSource with DioExecutor {
  MeRemoteDataSource(this._dio);

  final Dio _dio;

  Future<TeamProfile> me() => guard(() async {
        final res = await _dio.get('/me');
        return TeamProfile.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<List<SecurityEvent>> securityEvents() => guard(() async {
        final res = await _dio.get('/me/security-events');
        final data = (res.data as Map).cast<String, dynamic>();
        return ((data['events'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => SecurityEvent.fromJson(e.cast<String, dynamic>()))
            .toList();
      });

  Future<TeamProfile> uploadPhoto(List<int> bytes, String filename) => guard(() async {
        final form = FormData.fromMap({
          'photo': MultipartFile.fromBytes(bytes, filename: filename.isEmpty ? 'photo.jpg' : filename),
        });
        final res = await _dio.post('/me/photo', data: form);
        return TeamProfile.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<TeamProfile> removePhoto() => guard(() async {
        final res = await _dio.delete('/me/photo');
        return TeamProfile.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<String?> requestEmailChange({required String email, required String password}) => guard(() async {
        final res = await _dio.post('/me/email/request', data: {'email': email, 'password': password});
        final data = res.data;
        if (data is Map && data['sent_to'] != null) return data['sent_to'].toString();
        return null;
      });

  Future<TeamProfile> confirmEmailChange(String code) => guard(() async {
        final res = await _dio.post('/me/email/confirm', data: {'code': code});
        return TeamProfile.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<String?> requestPhoneChange({required String phoneNumber, required String password}) => guard(() async {
        final res = await _dio.post('/me/phone/request', data: {'phone_number': phoneNumber, 'password': password});
        final data = res.data;
        if (data is Map && data['sent_to'] != null) return data['sent_to'].toString();
        return null;
      });

  Future<TeamProfile> confirmPhoneChange(String code) => guard(() async {
        final res = await _dio.post('/me/phone/confirm', data: {'code': code});
        return TeamProfile.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<void> requestTwoFactorEnable() => guard(() => _dio.post('/me/two-factor/request'));

  Future<TeamProfile> enableTwoFactor(String code) => guard(() async {
        final res = await _dio.post('/me/two-factor/enable', data: {'code': code});
        return TeamProfile.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<TeamProfile> disableTwoFactor(String password) => guard(() async {
        final res = await _dio.post('/me/two-factor/disable', data: {'password': password});
        return TeamProfile.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<void> changePassword({required String oldPassword, required String newPassword}) => guard(
        () => _dio.post('/me/password', data: {'old_password': oldPassword, 'new_password': newPassword}),
      );
}

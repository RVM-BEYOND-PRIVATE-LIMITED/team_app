import 'package:dio/dio.dart';

import '../../domain/ess_models.dart';
import '../dio_executor.dart';

/// The kept-sign-in tokens `POST /api/ess/session` answers with.
class KeptSession {
  const KeptSession({
    required this.accessToken,
    required this.refreshToken,
    this.accessExpiresAt,
    this.sessionId,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime? accessExpiresAt;
  final String? sessionId;
}

/// Every call the Team RVM app makes to the ESS (`/api/ess`). Paths are
/// relative to the ESS base URL configured on the injected Dio.
class EssRemoteDataSource with DioExecutor {
  EssRemoteDataSource(this._dio);

  final Dio _dio;

  Map<String, dynamic> _body(Response<dynamic> res) => (res.data as Map).cast<String, dynamic>();

  Map<String, dynamic> _obj(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};

  List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) parse) => raw is List
      ? raw.whereType<Map>().map((e) => parse(e.cast<String, dynamic>())).toList(growable: false)
      : <T>[];

  // ── health / identity ────────────────────────────────────────────────────

  Future<EssHealth> health() =>
      guard(() async => EssHealth.fromJson(_body(await _dio.get('/health'))));

  Future<EssMe> me() => guard(() async => EssMe.fromJson(_body(await _dio.get('/me'))));

  Future<EssCapabilities> capabilities() =>
      guard(() async => EssCapabilities.fromJson(_body(await _dio.get('/me/capabilities'))));

  // ── kept sign-in (A3) ────────────────────────────────────────────────────

  Future<KeptSession> keepSignIn({required String installId, String? deviceLabel}) => guard(() async {
        final res = await _dio.post('/session', data: {
          'install_id': installId,
          if (deviceLabel != null && deviceLabel.trim().isNotEmpty) 'device_label': deviceLabel.trim(),
        });
        final data = _body(res);
        final session = _obj(data['session']);
        return KeptSession(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
          accessExpiresAt: DateTime.tryParse('${data['access_expires_at']}'),
          sessionId: session['id']?.toString(),
        );
      });

  Future<void> signOutEss() => guard(() async {
        await _dio.post('/session/sign-out');
      });

  Future<List<TeamSession>> sessions() => guard(() async => _list(
        _body(await _dio.get('/sessions'))['sessions'],
        TeamSession.fromJson,
      ));

  Future<void> endSession(String id) => guard(() async {
        await _dio.delete('/sessions/$id');
      });

  // ── one-field sign-in (A5) ───────────────────────────────────────────────

  Future<SignInResolution> resolveSignIn(String identifier) =>
      guard(() async => SignInResolution.fromJson(
            _body(await _dio.post('/sign-in/resolve', data: {'identifier': identifier})),
          ));

  // ── personal details (E9) ────────────────────────────────────────────────

  Future<PersonalDetails> readMyPersonal() => guard(() async => PersonalDetails.fromJson(
        _obj(_body(await _dio.get('/me/personal'))['personal']),
      ));

  Future<PersonalDetails> updateMyPersonal(Map<String, dynamic> patch) => guard(() async =>
      PersonalDetails.fromJson(_obj(_body(await _dio.put('/me/personal', data: patch))['personal'])));

  Future<({EmployeeCard employee, PersonalDetails personal})> employeePersonal(String employeeId) =>
      guard(() async {
        final data = _body(await _dio.get('/hr/employees/$employeeId/personal'));
        return (
          employee: EmployeeCard.fromJson(_obj(data['employee'])),
          personal: PersonalDetails.fromJson(_obj(data['personal'])),
        );
      });

  Future<({EmployeeCard employee, PersonalDetails personal})> updateEmployeePersonal(
          String employeeId, Map<String, dynamic> patch) =>
      guard(() async {
        final data = _body(await _dio.put('/hr/employees/$employeeId/personal', data: patch));
        return (
          employee: EmployeeCard.fromJson(_obj(data['employee'])),
          personal: PersonalDetails.fromJson(_obj(data['personal'])),
        );
      });

  // ── data requests (A8) ───────────────────────────────────────────────────

  Future<EssDataRequest> createMyDataRequest({required String kind, required String details}) =>
      guard(() async => EssDataRequest.fromJson(_obj(
            _body(await _dio.post('/me/data-requests', data: {'kind': kind, 'details': details}))['request'],
          )));

  Future<List<EssDataRequest>> myDataRequests() => guard(() async => _list(
        _body(await _dio.get('/me/data-requests'))['requests'],
        EssDataRequest.fromJson,
      ));

  Future<({List<EssDataRequest> requests, bool truncated})> hrDataRequests({String status = 'open'}) =>
      guard(() async {
        final data = _body(await _dio.get('/hr/data-requests', queryParameters: {'status': status}));
        return (requests: _list(data['requests'], EssDataRequest.fromJson), truncated: data['truncated'] == true);
      });

  Future<EssDataRequest> resolveDataRequest(String id, {required String status, String? note}) =>
      guard(() async => EssDataRequest.fromJson(_obj(
            _body(await _dio.patch('/hr/data-requests/$id', data: {
              'status': status,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            }))['request'],
          )));

  // ── attendance day + mock location (B1, B14) ─────────────────────────────

  Future<AttendanceDay> attendanceDay(String date) => guard(() async => AttendanceDay.fromJson(
        _body(await _dio.get('/attendance/day', queryParameters: {'date': date})),
      ));

  Future<MockLocationReport> reportMockLocation(Map<String, dynamic> body) => guard(() async =>
      MockLocationReport.fromJson(_obj(_body(await _dio.post('/attendance/mock-location', data: body))['report'])));

  Future<({List<MockLocationReport> reports, bool truncated})> mockLocationReports({
    String? from,
    String? to,
    String? branchId,
  }) =>
      guard(() async {
        final data = _body(await _dio.get('/hr/mock-location-reports', queryParameters: {
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          if (branchId != null) 'branch_id': branchId,
        }));
        return (reports: _list(data['reports'], MockLocationReport.fromJson), truncated: data['truncated'] == true);
      });

  // ── registered phones / HR reset (B8) ────────────────────────────────────

  Future<({List<RegisteredPhone> devices, bool truncated})> devices({
    String? branchId,
    String status = 'active',
  }) =>
      guard(() async {
        final data = _body(await _dio.get('/hr/devices', queryParameters: {
          'status': status,
          if (branchId != null) 'branch_id': branchId,
        }));
        return (devices: _list(data['devices'], RegisteredPhone.fromJson), truncated: data['truncated'] == true);
      });

  Future<int> resetDevices(Map<String, dynamic> body) => guard(() async {
        final data = _body(await _dio.post('/hr/devices/reset', data: body));
        return (data['reset'] as num?)?.toInt() ?? 0;
      });

  // ── 1E: profile, org, directory, team, praise ────────────────────────────

  Future<MyProfile> myProfile() =>
      guard(() async => MyProfile.fromJson(_body(await _dio.get('/me/profile'))));

  Future<OrgView> myOrg() => guard(() async => OrgView.fromJson(_body(await _dio.get('/me/org'))));

  Future<DirectoryPage> directory({String? query, String? branchId, String? departmentId}) =>
      guard(() async => DirectoryPage.fromJson(_body(await _dio.get('/directory', queryParameters: {
            if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
            if (branchId != null) 'branch_id': branchId,
            if (departmentId != null) 'department_id': departmentId,
          }))));

  Future<TeamTodayView> teamToday({String filter = 'all'}) => guard(() async =>
      TeamTodayView.fromJson(_body(await _dio.get('/team/today', queryParameters: {'filter': filter}))));

  Future<TeamOffWeek> teamOffThisWeek() =>
      guard(() async => TeamOffWeek.fromJson(_body(await _dio.get('/team/off-this-week'))));

  Future<PraisePage> myPraise({String? employeeId}) => guard(() async => PraisePage.fromJson(
      _body(await _dio.get('/me/praise', queryParameters: {if (employeeId != null) 'employee_id': employeeId}))));

  // ── 1C: requests, leave, balances, approvals ─────────────────────────────

  Future<EssRequest> createAttendanceRequest({
    required String type,
    required String day,
    required String reason,
    String? place,
    String? fixIn,
    String? fixOut,
  }) =>
      guard(() async => EssRequest.fromJson(_obj(_body(await _dio.post('/attendance-requests', data: {
            'type': type,
            'day': day,
            'reason': reason,
            if (place != null) 'place': place,
            if (fixIn != null) 'fix_in': fixIn,
            if (fixOut != null) 'fix_out': fixOut,
          }))['request'])));

  Future<List<EssRequest>> myAttendanceRequests() => guard(() async =>
      _list(_body(await _dio.get('/attendance-requests'))['requests'], EssRequest.fromJson));

  Future<EssRequest> withdrawAttendanceRequest(String id) => guard(() async =>
      EssRequest.fromJson(_obj(_body(await _dio.post('/attendance-requests/$id/withdraw'))['request'])));

  Future<EssRequest> createLeaveRequest({required String type, required String day, required String reason}) =>
      guard(() async => EssRequest.fromJson(_obj(_body(await _dio.post('/leave-requests', data: {
            'type': type,
            'day': day,
            'reason': reason,
          }))['request'])));

  Future<List<EssRequest>> myLeaveRequests() => guard(() async =>
      _list(_body(await _dio.get('/leave-requests'))['requests'], EssRequest.fromJson));

  Future<EssRequest> withdrawLeaveRequest(String id) => guard(() async =>
      EssRequest.fromJson(_obj(_body(await _dio.post('/leave-requests/$id/withdraw'))['request'])));

  Future<LeaveBalances> leaveBalances({String? month}) => guard(() async => LeaveBalances.fromJson(
      _body(await _dio.get('/leave/balances', queryParameters: {if (month != null) 'month': month}))));

  Future<ApprovalInbox> approvals({String status = 'pending'}) => guard(() async =>
      ApprovalInbox.fromJson(_body(await _dio.get('/approvals', queryParameters: {'status': status}))));

  Future<EssRequest> decideRequest({
    required String family,
    required String id,
    required String decision,
    String? note,
  }) =>
      guard(() async => EssRequest.fromJson(_obj(_body(await _dio.post('/approvals/$family/$id/decide', data: {
            'decision': decision,
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }))['request'])));

  Future<void> archiveRequest({required String family, required String id}) =>
      guard(() async => _dio.post('/approvals/$family/$id/archive'));

  // ── 1D: notifications ────────────────────────────────────────────────────

  Future<NotificationPage> notifications() =>
      guard(() async => NotificationPage.fromJson(_body(await _dio.get('/notifications'))));

  Future<void> readNotification(String id) =>
      guard(() async => _dio.post('/notifications/$id/read'));

  Future<int> readAllNotifications() => guard(() async {
        final data = _body(await _dio.post('/notifications/read-all'));
        return (data['marked'] as num?)?.toInt() ?? 0;
      });

  Future<NotificationSettings> notificationSettings() =>
      guard(() async => NotificationSettings.fromJson(_body(await _dio.get('/notifications/settings'))));

  Future<NotificationSettings> saveNotificationSettings(List<String> disabledCategories) =>
      guard(() async => NotificationSettings.fromJson(_body(await _dio.put('/notifications/settings',
          data: {'disabled_categories': disabledCategories}))));
}

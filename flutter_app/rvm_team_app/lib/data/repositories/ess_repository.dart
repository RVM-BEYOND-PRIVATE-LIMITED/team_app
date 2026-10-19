import 'package:core_network/core_network.dart';

import '../../domain/ess_models.dart';
import '../connectivity_guard.dart';
import '../datasources/ess_remote_data_source.dart';

/// One repository for the Team RVM ESS surface. Reads gate on connectivity;
/// writes pass through. The kept-sign-in exchange is persisted here, so the
/// rest of the app only sees tokens via [EssTokenStore]/[AuthSession].
class EssRepository with ConnectivityGuard {
  EssRepository({
    required EssRemoteDataSource remote,
    required EssTokenStore tokens,
    required this.connectivity,
  })  : _remote = remote,
        _tokens = tokens;

  final EssRemoteDataSource _remote;
  final EssTokenStore _tokens;

  @override
  final ConnectivityService connectivity;

  /// Gate the launch-time calls too: a cold start fires these the instant the
  /// app opens, often before the OS resolver/network is ready. Skipping the
  /// socket entirely while offline avoids a spurious `Failed host lookup` and
  /// lets the caller retry once the device reports online.
  Future<EssHealth> health() async {
    await ensureOnline();
    return _remote.health();
  }

  Future<EssMe> me() async {
    await ensureOnline();
    return _remote.me();
  }

  Future<EssCapabilities> capabilities() async {
    await ensureOnline();
    return _remote.capabilities();
  }

  /// Trade the fresh Scheduler sign-in for a kept, rotating one (task A3).
  /// Safe to call right after login; a failure must not block sign-in.
  Future<void> keepSignIn({String? deviceLabel}) async {
    final installId = await _tokens.installId();
    final kept = await _remote.keepSignIn(installId: installId, deviceLabel: deviceLabel);
    await _tokens.saveEssSession(
      accessToken: kept.accessToken,
      refreshToken: kept.refreshToken,
      accessExpiresAt: kept.accessExpiresAt,
    );
  }

  Future<void> signOut() async {
    try {
      await ensureOnline();
      await _remote.signOutEss();
    } finally {
      await _tokens.clearEssSession();
    }
  }

  Future<List<TeamSession>> sessions() async {
    await ensureOnline();
    return _remote.sessions();
  }

  Future<void> endSession(String id) async {
    await ensureOnline();
    await _remote.endSession(id);
  }

  Future<SignInResolution> resolveSignIn(String identifier) async {
    await ensureOnline();
    return _remote.resolveSignIn(identifier);
  }

  Future<PersonalDetails> personal() async {
    await ensureOnline();
    return _remote.readMyPersonal();
  }

  Future<PersonalDetails> updatePersonal(Map<String, dynamic> patch) async {
    await ensureOnline();
    return _remote.updateMyPersonal(patch);
  }

  Future<({EmployeeCard employee, PersonalDetails personal})> employeePersonal(String id) async {
    await ensureOnline();
    return _remote.employeePersonal(id);
  }

  Future<({EmployeeCard employee, PersonalDetails personal})> updateEmployeePersonal(
      String id, Map<String, dynamic> patch) async {
    await ensureOnline();
    return _remote.updateEmployeePersonal(id, patch);
  }

  Future<EssDataRequest> createDataRequest({required String kind, required String details}) async {
    await ensureOnline();
    return _remote.createMyDataRequest(kind: kind, details: details);
  }

  Future<List<EssDataRequest>> myDataRequests() async {
    await ensureOnline();
    return _remote.myDataRequests();
  }

  Future<({List<EssDataRequest> requests, bool truncated})> hrDataRequests({String status = 'open'}) async {
    await ensureOnline();
    return _remote.hrDataRequests(status: status);
  }

  Future<EssDataRequest> resolveDataRequest(String id, {required String status, String? note}) async {
    await ensureOnline();
    return _remote.resolveDataRequest(id, status: status, note: note);
  }

  Future<AttendanceDay> attendanceDay(String date) async {
    await ensureOnline();
    return _remote.attendanceDay(date);
  }

  Future<MockLocationReport> reportMockLocation(Map<String, dynamic> body) async {
    await ensureOnline();
    return _remote.reportMockLocation(body);
  }

  Future<({List<MockLocationReport> reports, bool truncated})> mockLocationReports({
    String? from,
    String? to,
    String? branchId,
  }) async {
    await ensureOnline();
    return _remote.mockLocationReports(from: from, to: to, branchId: branchId);
  }

  Future<({List<RegisteredPhone> devices, bool truncated})> devices({
    String? branchId,
    String status = 'active',
  }) async {
    await ensureOnline();
    return _remote.devices(branchId: branchId, status: status);
  }

  Future<int> resetDevices(Map<String, dynamic> body) async {
    await ensureOnline();
    return _remote.resetDevices(body);
  }

  // ── 1E: profile, org, directory, team, praise ────────────────────────────

  Future<MyProfile> myProfile() async {
    await ensureOnline();
    return _remote.myProfile();
  }

  Future<OrgView> myOrg() async {
    await ensureOnline();
    return _remote.myOrg();
  }

  Future<DirectoryPage> directory({String? query, String? branchId, String? departmentId}) async {
    await ensureOnline();
    return _remote.directory(query: query, branchId: branchId, departmentId: departmentId);
  }

  Future<TeamTodayView> teamToday({String filter = 'all'}) async {
    await ensureOnline();
    return _remote.teamToday(filter: filter);
  }

  Future<TeamOffWeek> teamOffThisWeek() async {
    await ensureOnline();
    return _remote.teamOffThisWeek();
  }

  Future<PraisePage> myPraise({String? employeeId}) async {
    await ensureOnline();
    return _remote.myPraise(employeeId: employeeId);
  }

  // ── 1C: requests, leave, balances, approvals ─────────────────────────────

  Future<EssRequest> createAttendanceRequest({
    required String type,
    required String day,
    required String reason,
    String? place,
    String? fixIn,
    String? fixOut,
  }) async {
    await ensureOnline();
    return _remote.createAttendanceRequest(type: type, day: day, reason: reason, place: place, fixIn: fixIn, fixOut: fixOut);
  }

  Future<List<EssRequest>> myAttendanceRequests() async {
    await ensureOnline();
    return _remote.myAttendanceRequests();
  }

  Future<EssRequest> withdrawAttendanceRequest(String id) async {
    await ensureOnline();
    return _remote.withdrawAttendanceRequest(id);
  }

  Future<EssRequest> createLeaveRequest({required String type, required String day, required String reason}) async {
    await ensureOnline();
    return _remote.createLeaveRequest(type: type, day: day, reason: reason);
  }

  Future<List<EssRequest>> myLeaveRequests() async {
    await ensureOnline();
    return _remote.myLeaveRequests();
  }

  Future<EssRequest> withdrawLeaveRequest(String id) async {
    await ensureOnline();
    return _remote.withdrawLeaveRequest(id);
  }

  Future<LeaveBalances> leaveBalances({String? month}) async {
    await ensureOnline();
    return _remote.leaveBalances(month: month);
  }

  Future<ApprovalInbox> approvals({String status = 'pending'}) async {
    await ensureOnline();
    return _remote.approvals(status: status);
  }

  Future<EssRequest> decideRequest({required String family, required String id, required String decision, String? note}) async {
    await ensureOnline();
    return _remote.decideRequest(family: family, id: id, decision: decision, note: note);
  }

  Future<void> archiveRequest({required String family, required String id}) async {
    await ensureOnline();
    return _remote.archiveRequest(family: family, id: id);
  }

  // ── 1D: notifications ────────────────────────────────────────────────────

  Future<NotificationPage> notifications() async {
    // The unread badge is read on launch; it must not be blocked by the gate.
    return _remote.notifications();
  }

  Future<void> readNotification(String id) async {
    await ensureOnline();
    return _remote.readNotification(id);
  }

  Future<int> readAllNotifications() async {
    await ensureOnline();
    return _remote.readAllNotifications();
  }

  Future<NotificationSettings> notificationSettings() async {
    await ensureOnline();
    return _remote.notificationSettings();
  }

  Future<NotificationSettings> saveNotificationSettings(List<String> disabledCategories) async {
    await ensureOnline();
    return _remote.saveNotificationSettings(disabledCategories);
  }
}

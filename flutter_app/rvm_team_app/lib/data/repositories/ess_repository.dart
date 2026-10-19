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
    int? minutes,
  }) async {
    await ensureOnline();
    return _remote.createAttendanceRequest(
        type: type, day: day, reason: reason, place: place, fixIn: fixIn, fixOut: fixOut, minutes: minutes);
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

  // ── 2A: the Wall ─────────────────────────────────────────────────────────

  Future<WallSettings> wallSettings() async {
    await ensureOnline();
    return _remote.wallSettings();
  }

  Future<WallFeed> wallFeed({String? scope, String? before}) async {
    await ensureOnline();
    return _remote.wallFeed(scope: scope, before: before);
  }

  Future<WallPostDetail> wallPost(String id) async {
    await ensureOnline();
    return _remote.wallPost(id);
  }

  Future<WallPost> createWallPost({
    required String body,
    String kind = 'post',
    String? scope,
    Map<String, dynamic>? poll,
    List<Map<String, dynamic>>? attachments,
  }) async {
    await ensureOnline();
    return _remote.createWallPost(body: body, kind: kind, scope: scope, poll: poll, attachments: attachments);
  }

  Future<List<WallReactionGroup>> postReactions(String id) async {
    await ensureOnline();
    return _remote.postReactions(id);
  }

  Future<List<WallReactionGroup>> commentReactions(String id) async {
    await ensureOnline();
    return _remote.commentReactions(id);
  }

  Future<void> addPollOption(String id, String label) async {
    await ensureOnline();
    return _remote.addPollOption(id, label);
  }

  Future<void> closePoll(String id) async {
    await ensureOnline();
    return _remote.closePoll(id);
  }

  Future<String?> putMyPhoto({required String base64, required String contentType}) async {
    await ensureOnline();
    return _remote.putMyPhoto(base64: base64, contentType: contentType);
  }

  Future<void> registerPushDevice({required String token, String? deviceLabel, String? installId}) async {
    await ensureOnline();
    return _remote.registerPushDevice(token: token, deviceLabel: deviceLabel, installId: installId);
  }

  Future<void> revokePushDevice(String id) async {
    await ensureOnline();
    return _remote.revokePushDevice(id);
  }

  Future<WallPost> editWallPost(String id, String body) async {
    await ensureOnline();
    return _remote.editWallPost(id, body);
  }

  Future<void> deleteWallComment(String id) async {
    await ensureOnline();
    return _remote.deleteWallComment(id);
  }

  Future<WallComment> editWallComment(String id, String body) async {
    await ensureOnline();
    return _remote.editWallComment(id, body);
  }

  Future<({WallReactionCounts counts, String? myReaction})> reactToComment(String id, String reaction) async {
    await ensureOnline();
    return _remote.reactToComment(id, reaction);
  }

  Future<({WallReactionCounts counts, String? myReaction})> unreactToComment(String id) async {
    await ensureOnline();
    return _remote.unreactToComment(id);
  }

  Future<void> reportPost(String id, {required String reason, String? detail}) async {
    await ensureOnline();
    return _remote.reportPost(id, reason: reason, detail: detail);
  }

  Future<void> reportComment(String id, {required String reason, String? detail}) async {
    await ensureOnline();
    return _remote.reportComment(id, reason: reason, detail: detail);
  }

  Future<void> withdrawPollVote(String id) async {
    await ensureOnline();
    return _remote.withdrawPollVote(id);
  }

  Future<bool> celebrationOptout() async {
    await ensureOnline();
    return _remote.celebrationOptout();
  }

  Future<void> setCelebrationOptout(bool hidden) async {
    await ensureOnline();
    return _remote.setCelebrationOptout(hidden);
  }

  Future<void> deleteWallPost(String id) async {
    await ensureOnline();
    return _remote.deleteWallPost(id);
  }

  Future<({WallReactionCounts counts, String? myReaction})> reactToPost(String id, String reaction) async {
    await ensureOnline();
    return _remote.reactToPost(id, reaction);
  }

  Future<({WallReactionCounts counts, String? myReaction})> unreactToPost(String id) async {
    await ensureOnline();
    return _remote.unreactToPost(id);
  }

  Future<WallComment> addWallComment({required String postId, required String body, String? parentId}) async {
    await ensureOnline();
    return _remote.addWallComment(postId: postId, body: body, parentId: parentId);
  }

  Future<WallPost> createPraise({
    required String employeeId,
    required String badge,
    required String reason,
    String scope = 'org',
    List<Map<String, dynamic>>? attachments,
  }) async {
    await ensureOnline();
    return _remote.createPraise(employeeId: employeeId, badge: badge, reason: reason, scope: scope, attachments: attachments);
  }

  Future<List<WallAnnouncement>> wallAnnouncements() async {
    await ensureOnline();
    return _remote.wallAnnouncements();
  }

  Future<void> readAnnouncement(String id) async {
    await ensureOnline();
    return _remote.readAnnouncement(id);
  }

  Future<void> ackAnnouncement(String id) async {
    await ensureOnline();
    return _remote.ackAnnouncement(id);
  }

  Future<WallCelebrations> wallCelebrations() async {
    await ensureOnline();
    return _remote.wallCelebrations();
  }

  Future<void> sendWish({required String employeeId, required String occasion, required String body}) async {
    await ensureOnline();
    return _remote.sendWish(employeeId: employeeId, occasion: occasion, body: body);
  }

  Future<void> votePoll({required String pollId, required List<String> optionIds}) async {
    await ensureOnline();
    return _remote.votePoll(pollId: pollId, optionIds: optionIds);
  }

  // ── 2B: Helpdesk ─────────────────────────────────────────────────────────

  Future<HelpdeskSettings> helpdeskCategories() async {
    await ensureOnline();
    return _remote.helpdeskCategories();
  }

  Future<List<HelpdeskTicket>> myTickets({String? status}) async {
    await ensureOnline();
    return _remote.myTickets(status: status);
  }

  Future<HelpdeskTicket> raiseTicket({required String category, required String subject, required String body, bool anonymous = false}) async {
    await ensureOnline();
    return _remote.raiseTicket(category: category, subject: subject, body: body, anonymous: anonymous);
  }

  Future<HelpdeskTicketDetail> ticket(String id) async {
    await ensureOnline();
    return _remote.ticket(id);
  }

  Future<HelpdeskMessage> addTicketComment({required String id, required String body}) async {
    await ensureOnline();
    return _remote.addTicketComment(id: id, body: body);
  }

  Future<HelpdeskTicket> ticketAction(String id, String action, {Map<String, dynamic>? data}) async {
    await ensureOnline();
    return _remote.ticketAction(id, action, data: data);
  }

  Future<HelpdeskTicket> assignTicket({required String id, required String employeeId, String? note}) async {
    await ensureOnline();
    return _remote.assignTicket(id: id, employeeId: employeeId, note: note);
  }

  Future<HelpdeskQueue> helpdeskQueue({String? status, String? category}) async {
    await ensureOnline();
    return _remote.helpdeskQueue(status: status, category: category);
  }

  // ── 2C: documents, change requests, bank details, ID card ────────────────

  Future<DocumentPage> myDocuments() async {
    await ensureOnline();
    return _remote.myDocuments();
  }

  Future<EssDocument> uploadDocument({
    required String docType,
    required String fileName,
    required String contentType,
    required String base64,
    String? remark,
  }) async {
    await ensureOnline();
    return _remote.uploadDocument(docType: docType, fileName: fileName, contentType: contentType, base64: base64, remark: remark);
  }

  Future<String?> documentFileUrl(String id) async {
    await ensureOnline();
    return _remote.documentFileUrl(id);
  }

  Future<List<ChangeRequest>> myChangeRequests() async {
    await ensureOnline();
    return _remote.myChangeRequests();
  }

  Future<ChangeRequest> createChangeRequest({required String field, String? oldValue, required String newValue, required String reason}) async {
    await ensureOnline();
    return _remote.createChangeRequest(field: field, oldValue: oldValue, newValue: newValue, reason: reason);
  }

  Future<BankDetails?> myBankDetails() async {
    await ensureOnline();
    return _remote.myBankDetails();
  }

  Future<BankDetails> saveBankDetails({
    required String bankName,
    String? branchName,
    required String accountNumber,
    required String ifscCode,
    String? upiId,
    required String consentName,
  }) async {
    await ensureOnline();
    return _remote.saveBankDetails(
      bankName: bankName,
      branchName: branchName,
      accountNumber: accountNumber,
      ifscCode: ifscCode,
      upiId: upiId,
      consentName: consentName,
    );
  }

  Future<IdCard> myIdCard() async {
    await ensureOnline();
    return _remote.myIdCard();
  }

  // ── 2D ───────────────────────────────────────────────────────────────────

  Future<LeadersOverview> leadersOverview() async {
    await ensureOnline();
    return _remote.leadersOverview();
  }

  Future<FacultyDay> facultyDay({String? date}) async {
    await ensureOnline();
    return _remote.facultyDay(date: date);
  }

  Future<ApprovalChain> approvalChain(String family, String id) async {
    await ensureOnline();
    return _remote.approvalChain(family, id);
  }

  // ── HR desk ──────────────────────────────────────────────────────────────

  Future<List<RequestLimit>> requestLimits() async {
    await ensureOnline();
    return _remote.requestLimits();
  }

  Future<void> setRequestLimit(String type, {int? count, int? minutes}) async {
    await ensureOnline();
    return _remote.setRequestLimit(type, count: count, minutes: minutes);
  }

  Future<EssRequest> cancelRequest(String family, String id, String reason) async {
    await ensureOnline();
    return _remote.cancelRequest(family, id, reason);
  }

  Future<List<ChangeRequest>> hrChangeRequests() async {
    await ensureOnline();
    return _remote.hrChangeRequests();
  }

  Future<ChangeRequest> decideChangeRequest(String id, {required bool approve, String? note}) async {
    await ensureOnline();
    return _remote.decideChangeRequest(id, approve: approve, note: note);
  }

  Future<DocumentPage> hrEmployeeDocuments(String employeeId) async {
    await ensureOnline();
    return _remote.hrEmployeeDocuments(employeeId);
  }

  Future<String?> hrDocumentFileUrl(String employeeId, String documentId) async {
    await ensureOnline();
    return _remote.hrDocumentFileUrl(employeeId, documentId);
  }

  Future<EssDocument> verifyDocument(String employeeId, String documentId) async {
    await ensureOnline();
    return _remote.verifyDocument(employeeId, documentId);
  }

  Future<EssDocument> rejectDocument(String employeeId, String documentId, String reason) async {
    await ensureOnline();
    return _remote.rejectDocument(employeeId, documentId, reason);
  }

  Future<void> deleteDocument(String employeeId, String documentId) async {
    await ensureOnline();
    return _remote.deleteDocument(employeeId, documentId);
  }

  Future<BankDetails?> hrEmployeeBank(String employeeId) async {
    await ensureOnline();
    return _remote.hrEmployeeBank(employeeId);
  }

  // ── Wall moderation / announcements ──────────────────────────────────────

  Future<WallAnnouncement> createAnnouncement({
    required String title,
    required String body,
    bool needsAck = false,
    String? closesOn,
    bool pinned = false,
  }) async {
    await ensureOnline();
    return _remote.createAnnouncement(title: title, body: body, needsAck: needsAck, closesOn: closesOn, pinned: pinned);
  }

  Future<List<WallAnnouncement>> hrAnnouncements() async {
    await ensureOnline();
    return _remote.hrAnnouncements();
  }

  Future<Map<String, int>> announcementCounts(String id) async {
    await ensureOnline();
    return _remote.announcementCounts(id);
  }

  Future<void> hidePost(String id, String reason) async {
    await ensureOnline();
    return _remote.hidePost(id, reason);
  }

  Future<void> hideComment(String id, String reason) async {
    await ensureOnline();
    return _remote.hideComment(id, reason);
  }

  Future<List<WallReport>> wallReports({String status = 'open'}) async {
    await ensureOnline();
    return _remote.wallReports(status: status);
  }

  Future<void> resolveReport(String id, {required bool hidden, String? note}) async {
    await ensureOnline();
    return _remote.resolveReport(id, hidden: hidden, note: note);
  }

  Future<List<ModerationEntry>> moderationLog() async {
    await ensureOnline();
    return _remote.moderationLog();
  }

}

import 'package:core_network/core_network.dart';

import '../../domain/team_stage2_models.dart';
import '../connectivity_guard.dart';
import '../datasources/team_stage2_remote_data_source.dart';

/// The Stage 2/3 Scheduler calls (#52–#58), with the online check in front.
class TeamStage2Repository with ConnectivityGuard {
  TeamStage2Repository(
      {required TeamStage2RemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final TeamStage2RemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<T> _read<T>(Future<T> Function() run) async {
    await ensureOnline();
    return run();
  }

  // security
  Future<TeamAccess> access() => _read(_remote.access);
  Future<bool> unlock({String? key}) =>
      _read(() => _remote.unlock(key: key));
  Future<List<TeamSecurityAlert>> securityAlerts({int days = 7}) =>
      _read(() => _remote.securityAlerts(days: days));
  Future<List<Map<String, dynamic>>> deviceRequests() =>
      _read(_remote.deviceRequests);
  Future<void> decideDevice(String id,
          {required bool approve, String? note, String? key}) =>
      _read(() =>
          _remote.decideDevice(id, approve: approve, note: note, key: key));

  // ops
  Future<List<PendingCount>> pendingCounts() => _read(_remote.pendingCounts);
  Future<List<AbsentStreak>> absentStreaks() => _read(_remote.absentStreaks);
  Future<BranchHealth> branchHealth({String? from, String? to}) =>
      _read(() => _remote.branchHealth(from: from, to: to));
  Future<BranchHealthMoney> branchHealthMoney({String? from, String? to}) =>
      _read(() => _remote.branchHealthMoney(from: from, to: to));

  // fees
  Future<FeeList> fees({String tab = 'today', String source = 'current'}) =>
      _read(() => _remote.fees(tab: tab, source: source));
  Future<List<FeeHistoryRow>> feeHistory(String admissionId) =>
      _read(() => _remote.feeHistory(admissionId));
  Future<String> revealFee(String admissionId, {String? key}) =>
      _read(() => _remote.revealFee(admissionId, key: key));
  Future<void> saveFeeOutcome(String admissionId, FeeOutcomeDraft draft,
          {String? key}) =>
      _read(() => _remote.saveFeeOutcome(admissionId, draft, key: key));
  Future<FeeShares> feeShares() => _read(_remote.feeShares);
  Future<void> addFeeShare(String userId, {String? key}) =>
      _read(() => _remote.addFeeShare(userId, key: key));
  Future<void> removeFeeShare(String userId, {String? key}) =>
      _read(() => _remote.removeFeeShare(userId, key: key));

  // scorecards
  Future<Scorecard> myScorecard({String period = 'week'}) =>
      _read(() => _remote.myScorecard(period: period));
  Future<Scorecard> branchScorecards({String period = 'week'}) =>
      _read(() => _remote.branchScorecards(period: period));
  Future<Scorecard> ceoScorecard({String period = 'week'}) =>
      _read(() => _remote.ceoScorecard(period: period));
  Future<TargetsView> targets({String period = 'week'}) =>
      _read(() => _remote.targets(period: period));

  // social
  Future<SocialMe> socialMe() => _read(_remote.socialMe);
  Future<List<SocialShoot>> myShoots() => _read(_remote.myShoots);
  Future<SocialHome> socialHome() => _read(_remote.socialHome);
  Future<List<SocialCard>> socialCards(
          {String? stage, String? editor, String? account}) =>
      _read(() =>
          _remote.socialCards(stage: stage, editor: editor, account: account));
  Future<SocialCard> socialCard(String id) =>
      _read(() => _remote.socialCard(id));
  Future<void> markCardDone(String id, {String? key}) =>
      _read(() => _remote.markCardDone(id, key: key));
  Future<void> moveCard(String id, Map<String, dynamic> patch,
          {String? key}) =>
      _read(() => _remote.moveCard(id, patch, key: key));
  Future<List<SocialShoot>> shoots({String? from, String? to}) =>
      _read(() => _remote.shoots(from: from, to: to));
  Future<List<FreeSlot>> freeSlots({
    required String from,
    required List<String> employeeIds,
    int minutes = 60,
  }) =>
      _read(() => _remote.freeSlots(
          from: from, employeeIds: employeeIds, minutes: minutes));
  Future<void> bookShoot(Map<String, dynamic> body, {String? key}) =>
      _read(() => _remote.bookShoot(body, key: key));
  Future<List<SocialAccount>> socialAccounts() => _read(_remote.socialAccounts);

  // desk
  Future<List<DeskQueue>> deskCounts() => _read(_remote.deskCounts);
  Future<List<LinkRequest>> linkRequests() => _read(_remote.linkRequests);
  Future<List<LinkCandidate>> linkCandidates(String query) =>
      _read(() => _remote.linkCandidates(query));
  Future<void> linkStudent(
          {required String admissionId,
          required String phone,
          String? requestId,
          String? reason,
          String? key}) =>
      _read(() => _remote.linkStudent(
          admissionId: admissionId,
          phone: phone,
          requestId: requestId,
          reason: reason,
          key: key));
  Future<List<PhoneChangeRequest>> phoneChanges() => _read(_remote.phoneChanges);
  Future<void> decidePhoneChange(String id,
          {required bool approve, required String reason, String? key}) =>
      _read(() => _remote.decidePhoneChange(id,
          approve: approve, reason: reason, key: key));
  Future<List<ViewRequest>> viewRequests() => _read(_remote.viewRequests);
  Future<void> decideViewRequest(String id,
          {required bool grant, int views = 1, String? note, String? key}) =>
      _read(() => _remote.decideViewRequest(id,
          grant: grant, views: views, note: note, key: key));

  // placement
  Future<List<PlacementFollowup>> companyFollowups({String tab = 'today'}) =>
      _read(() => _remote.companyFollowups(tab: tab));
  Future<String> revealCompany(String entryId, {String? key}) =>
      _read(() => _remote.revealCompany(entryId, key: key));
  Future<void> recordCompanyCall(String entryId,
          {required String outcome,
          required String status,
          String? inProgressState,
          String? nextFollowUpOn,
          String? remark,
          String? key}) =>
      _read(() => _remote.recordCompanyCall(entryId,
          outcome: outcome,
          status: status,
          inProgressState: inProgressState,
          nextFollowUpOn: nextFollowUpOn,
          remark: remark,
          key: key));
  Future<List<PlacementVerification>> verifications(
          {String status = 'pending'}) =>
      _read(() => _remote.verifications(status: status));
  Future<void> placementCall(String id,
          {required String kind,
          required String outcome,
          String? note,
          String? key}) =>
      _read(() => _remote.placementCall(id,
          kind: kind, outcome: outcome, note: note, key: key));
  Future<Map<String, dynamic>> decidePlacement(String id,
          {required bool approve, required String note, String? key}) =>
      _read(() =>
          _remote.decidePlacement(id, approve: approve, note: note, key: key));

  // complaints
  Future<List<ComplaintRow>> complaints({String filter = 'open'}) =>
      _read(() => _remote.complaints(filter: filter));
  Future<ComplaintThread> complaint(String id) =>
      _read(() => _remote.complaint(id));
  Future<void> replyComplaint(String id, String body, {String? key}) =>
      _read(() => _remote.replyComplaint(id, body, key: key));
  Future<void> setComplaintStatus(String id,
          {required String status, String? note, String? key}) =>
      _read(() => _remote.setComplaintStatus(id,
          status: status, note: note, key: key));

  // moderation
  Future<List<ModerationReport>> moderationReports() =>
      _read(_remote.moderationReports);
  Future<void> hidePost(String id, String reason, {String? key}) =>
      _read(() => _remote.hidePost(id, reason, key: key));
  Future<void> restorePost(String id, {String? note, String? key}) =>
      _read(() => _remote.restorePost(id, note: note, key: key));
  Future<void> warnMember(String id,
          {required String reason, String? postId, String? key}) =>
      _read(() => _remote.warnMember(id,
          reason: reason, postId: postId, key: key));

  // marks
  Future<List<BatchTest>> batchTests(String batchId) =>
      _read(() => _remote.batchTests(batchId));
  Future<void> saveTest(Map<String, dynamic> body, {String? key}) =>
      _read(() => _remote.saveTest(body, key: key));
}

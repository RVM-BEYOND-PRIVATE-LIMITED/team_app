import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

import '../../domain/team_stage2_models.dart';
import '../../router/module_routes.dart';
import '../dio_executor.dart';
import '../module_request.dart';

/// The Scheduler routes behind Stage 2/3 (#52–#58): the Team app access facts,
/// the fees and ops lists, scorecards, social, the student desk, placement,
/// complaints, moderation and test marks.
///
/// Every request carries its module tag, so a 404 `NOT_FOUND` from a closed
/// switch reads as "module off". A write also carries an Idempotency-Key; a
/// form passes its own key so a retry is one action.
class TeamStage2RemoteDataSource with DioExecutor {
  TeamStage2RemoteDataSource(this._dio);

  final Dio _dio;

  Options _opts(TeamModule? module, {String? key}) => Options(extra: {
        if (module != null) ...?module.requestOptions.extra,
        if (key != null && key.isNotEmpty)
          IdempotencyInterceptor.extraKey: key,
      });

  Map<String, dynamic> _map(Object? body) =>
      body is Map ? body.cast<String, dynamic>() : (throw const ParseFailure());

  // ── security (#52) ──────────────────────────────────────────────────────

  Future<TeamAccess> access() => guard(() async {
        final res = await _dio.get<Object?>('/team/access',
            options: _opts(TeamModule.crm));
        return TeamAccess.fromJson(_map(bodyOf(res)));
      });

  Future<bool> unlock({String? key}) => guard(() async {
        final res = await _dio.post<Object?>('/team/access/unlock',
            options: _opts(TeamModule.crm, key: key));
        return _map(bodyOf(res))['unlocked'] == true;
      });

  Future<List<TeamSecurityAlert>> securityAlerts({int days = 7}) =>
      guard(() async {
        final res = await _dio.get<Object?>('/team/security/alerts',
            queryParameters: {'days': days}, options: _opts(TeamModule.crm));
        final body = _map(bodyOf(res));
        return [
          for (final a in (body['alerts'] as List? ?? const []))
            if (TeamSecurityAlert.tryParse(a) case final alert?) alert,
        ];
      });

  Future<List<Map<String, dynamic>>> deviceRequests() => guard(() async {
        final res = await _dio.get<Object?>(
            '/hr/attendance-admin/device-requests',
            options: _opts(null));
        final body = _map(bodyOf(res));
        final rows = body['requests'] ?? body['items'] ?? const [];
        return [
          if (rows is List)
            for (final r in rows)
              if (r is Map) r.cast<String, dynamic>(),
        ];
      });

  Future<void> decideDevice(String id,
          {required bool approve, String? note, String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/hr/attendance-admin/device-requests/$id/decide',
          data: {
            'decision': approve ? 'approve' : 'reject',
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          },
          options: _opts(null, key: key),
        );
        bodyOf(res);
      });

  // ── pending counts and branch health (#53) ──────────────────────────────

  Future<List<PendingCount>> pendingCounts() => guard(() async {
        final res = await _dio.get<Object?>('/team/pending-counts',
            options: _opts(TeamModule.scorecards));
        final body = _map(bodyOf(res));
        return [
          for (final i in (body['items'] as List? ?? const []))
            PendingCount.fromJson(i),
        ];
      });

  Future<List<AbsentStreak>> absentStreaks() => guard(() async {
        final res = await _dio.get<Object?>('/team/absent-streaks',
            options: _opts(TeamModule.desk));
        final body = _map(bodyOf(res));
        return [
          for (final s in (body['students'] as List? ?? const []))
            if (AbsentStreak.tryParse(s) case final row?) row,
        ];
      });

  Future<BranchHealth> branchHealth({String? from, String? to}) =>
      guard(() async {
        final res = await _dio.get<Object?>('/team/branch-health',
            queryParameters: {
              if (from != null) 'from': from,
              if (to != null) 'to': to,
            },
            options: _opts(TeamModule.scorecards));
        return BranchHealth.fromJson(_map(bodyOf(res)));
      });

  Future<BranchHealthMoney> branchHealthMoney({String? from, String? to}) =>
      guard(() async {
        final res = await _dio.get<Object?>('/team/branch-health/money',
            queryParameters: {
              if (from != null) 'from': from,
              if (to != null) 'to': to,
            },
            options: _opts(TeamModule.scorecards));
        return BranchHealthMoney.fromJson(_map(bodyOf(res)));
      });

  // ── fees follow-up (#53) ────────────────────────────────────────────────

  Future<FeeList> fees({String tab = 'today', String source = 'current'}) =>
      guard(() async {
        final res = await _dio.get<Object?>('/team/fees-followups',
            queryParameters: {'tab': tab, 'source': source},
            options: _opts(TeamModule.fees));
        return FeeList.fromJson(_map(bodyOf(res)));
      });

  Future<List<FeeHistoryRow>> feeHistory(String admissionId) =>
      guard(() async {
        final res = await _dio.get<Object?>(
            '/team/fees-followups/$admissionId/history',
            options: _opts(TeamModule.fees));
        final body = _map(bodyOf(res));
        return [
          for (final h in (body['history'] as List? ?? const []))
            if (FeeHistoryRow.tryParse(h) case final row?) row,
        ];
      });

  Future<String> revealFee(String admissionId, {String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/team/fees-followups/$admissionId/reveal',
            options: _opts(TeamModule.fees, key: key));
        final phone = _map(bodyOf(res))['phone'];
        if (phone is! String || phone.isEmpty) throw const ParseFailure();
        return phone;
      });

  Future<void> saveFeeOutcome(String admissionId, FeeOutcomeDraft draft,
          {String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/team/fees-followups/$admissionId/outcome',
            data: draft.toJson(),
            options: _opts(TeamModule.fees, key: key));
        bodyOf(res);
      });

  Future<FeeShares> feeShares() => guard(() async {
        final res = await _dio.get<Object?>('/team/fees-followups/shares',
            options: _opts(TeamModule.fees));
        return FeeShares.fromJson(_map(bodyOf(res)));
      });

  Future<void> addFeeShare(String userId, {String? key}) => guard(() async {
        final res = await _dio.post<Object?>('/team/fees-followups/shares',
            data: {'user_id': userId},
            options: _opts(TeamModule.fees, key: key));
        bodyOf(res);
      });

  Future<void> removeFeeShare(String userId, {String? key}) =>
      guard(() async {
        final res = await _dio.delete<Object?>(
            '/team/fees-followups/shares/$userId',
            options: _opts(TeamModule.fees, key: key));
        bodyOf(res);
      });

  // ── scorecards (#55) ────────────────────────────────────────────────────

  Future<Scorecard> myScorecard({String period = 'week'}) => guard(() async {
        final res = await _dio.get<Object?>('/team/scorecards/me',
            queryParameters: {'period': period},
            options: _opts(TeamModule.scorecards));
        return Scorecard.fromJson(_map(bodyOf(res)));
      });

  Future<Scorecard> branchScorecards({String period = 'week'}) =>
      guard(() async {
        final res = await _dio.get<Object?>('/team/scorecards/branches',
            queryParameters: {'period': period},
            options: _opts(TeamModule.scorecards));
        return Scorecard.fromJson(_map(bodyOf(res)));
      });

  Future<Scorecard> ceoScorecard({String period = 'week'}) => guard(() async {
        final res = await _dio.get<Object?>('/team/scorecards/ceo',
            queryParameters: {'period': period},
            options: _opts(TeamModule.scorecards));
        return Scorecard.fromJson(_map(bodyOf(res)));
      });

  Future<TargetsView> targets({String period = 'week'}) => guard(() async {
        final res = await _dio.get<Object?>('/team/targets',
            queryParameters: {'period': period},
            options: _opts(TeamModule.scorecards));
        return TargetsView.fromJson(_map(bodyOf(res)));
      });

  // ── My Tasks and social (#54) ───────────────────────────────────────────

  Future<SocialMe> socialMe() => guard(() async {
        final res = await _dio.get<Object?>('/social/me',
            options: _opts(TeamModule.tasks));
        return SocialMe.fromJson(_map(bodyOf(res)));
      });

  Future<List<SocialShoot>> myShoots() => guard(() async {
        final res = await _dio.get<Object?>('/social/me/shoots',
            options: _opts(TeamModule.tasks));
        final body = _map(bodyOf(res));
        return [
          for (final s in (body['shoots'] as List? ?? const []))
            if (SocialShoot.tryParse(s) case final shoot?) shoot,
        ];
      });

  Future<SocialHome> socialHome() => guard(() async {
        final res = await _dio.get<Object?>('/social/home',
            options: _opts(TeamModule.social));
        return SocialHome.fromJson(_map(bodyOf(res)));
      });

  Future<List<SocialCard>> socialCards(
          {String? stage, String? editor, String? account}) =>
      guard(() async {
        final res = await _dio.get<Object?>('/social/cards',
            queryParameters: {
              if (stage != null) 'stage': stage,
              if (editor != null) 'editor': editor,
              if (account != null) 'account': account,
            },
            options: _opts(TeamModule.social));
        final body = _map(bodyOf(res));
        return [
          for (final c in (body['cards'] as List? ?? const []))
            if (SocialCard.tryParse(c) case final card?) card,
        ];
      });

  Future<SocialCard> socialCard(String id) => guard(() async {
        final res = await _dio.get<Object?>('/social/cards/$id',
            options: _opts(TeamModule.social));
        final card = SocialCard.tryParse(bodyOf(res));
        if (card == null) throw const ParseFailure();
        return card;
      });

  Future<void> markCardDone(String id, {String? key}) => guard(() async {
        final res = await _dio.post<Object?>('/social/cards/$id/done',
            options: _opts(TeamModule.social, key: key));
        bodyOf(res);
      });

  Future<void> moveCard(String id, Map<String, dynamic> patch,
          {String? key}) =>
      guard(() async {
        final res = await _dio.patch<Object?>('/social/cards/$id',
            data: patch, options: _opts(TeamModule.social, key: key));
        bodyOf(res);
      });

  Future<List<SocialShoot>> shoots({String? from, String? to}) =>
      guard(() async {
        final res = await _dio.get<Object?>('/social/shoots',
            queryParameters: {
              if (from != null) 'from': from,
              if (to != null) 'to': to,
            },
            options: _opts(TeamModule.social));
        final body = _map(bodyOf(res));
        return [
          for (final s in (body['shoots'] as List? ?? const []))
            if (SocialShoot.tryParse(s) case final shoot?) shoot,
        ];
      });

  Future<List<FreeSlot>> freeSlots({
    required String from,
    required List<String> employeeIds,
    int minutes = 60,
  }) =>
      guard(() async {
        final res = await _dio.post<Object?>('/social/free-slots',
            data: {
              'from': from,
              'minutes': minutes,
              'employees': employeeIds,
            },
            options: _opts(TeamModule.social));
        final body = _map(bodyOf(res));
        return [
          for (final s in (body['slots'] as List? ?? const []))
            if (FreeSlot.tryParse(s) case final slot?) slot,
        ];
      });

  Future<void> bookShoot(Map<String, dynamic> body, {String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>('/social/shoots',
            data: body, options: _opts(TeamModule.social, key: key));
        bodyOf(res);
      });

  Future<List<SocialAccount>> socialAccounts() => guard(() async {
        final res = await _dio.get<Object?>('/social/accounts',
            options: _opts(TeamModule.social));
        final body = _map(bodyOf(res));
        return [
          for (final a in (body['accounts'] as List? ?? const []))
            if (SocialAccount.tryParse(a) case final account?) account,
        ];
      });

  // ── student desk (#56) ──────────────────────────────────────────────────

  Future<List<DeskQueue>> deskCounts() => guard(() async {
        final res = await _dio.get<Object?>('/student-desk/counts',
            options: _opts(TeamModule.desk));
        final body = _map(bodyOf(res));
        final out = <DeskQueue>[];
        for (final entry in body.entries) {
          if (entry.value is Map) {
            out.add(DeskQueue.fromJson(
                (entry.value as Map).cast<String, dynamic>(),
                key: entry.key));
          } else if (entry.value is num) {
            out.add(DeskQueue(
                key: entry.key,
                count: (entry.value as num).toInt(),
                available: true));
          }
        }
        return out;
      });

  Future<List<LinkRequest>> linkRequests() => guard(() async {
        final res = await _dio.get<Object?>('/student-desk/link-requests',
            options: _opts(TeamModule.desk));
        final body = _map(bodyOf(res));
        return [
          for (final r in (body['requests'] as List? ?? const []))
            if (LinkRequest.tryParse(r) case final request?) request,
        ];
      });

  Future<List<LinkCandidate>> linkCandidates(String query) =>
      guard(() async {
        final res = await _dio.get<Object?>('/student-desk/link-candidates',
            queryParameters: {'q': query},
            options: _opts(TeamModule.desk));
        final body = _map(bodyOf(res));
        return [
          for (final c in (body['candidates'] as List? ?? const []))
            if (LinkCandidate.tryParse(c) case final candidate?) candidate,
        ];
      });

  Future<void> linkStudent(
          {required String admissionId,
          required String phone,
          String? requestId,
          String? reason,
          String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>('/student-desk/links',
            data: {
              'admission_id': admissionId,
              if (phone.isNotEmpty) 'phone': phone,
              if (requestId != null) 'request_id': requestId,
              'reason': reason ?? 'Linked from the Team app',
            },
            options: _opts(TeamModule.desk, key: key));
        bodyOf(res);
      });

  Future<List<PhoneChangeRequest>> phoneChanges() => guard(() async {
        final res = await _dio.get<Object?>(
            '/student-desk/phone-change-requests',
            options: _opts(TeamModule.desk));
        final body = _map(bodyOf(res));
        return [
          for (final r in (body['requests'] as List? ?? const []))
            if (PhoneChangeRequest.tryParse(r) case final request?) request,
        ];
      });

  Future<void> decidePhoneChange(String id,
          {required bool approve, required String reason, String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/student-desk/phone-change-requests/$id/decide',
            data: {'decision': approve ? 'approve' : 'reject', 'reason': reason},
            options: _opts(TeamModule.desk, key: key));
        bodyOf(res);
      });

  Future<List<ViewRequest>> viewRequests() => guard(() async {
        final res = await _dio.get<Object?>('/student-desk/view-requests',
            options: _opts(TeamModule.desk));
        final body = _map(bodyOf(res));
        return [
          for (final r in (body['requests'] as List? ?? const []))
            if (ViewRequest.tryParse(r) case final request?) request,
        ];
      });

  Future<void> decideViewRequest(String id,
          {required bool grant,
          int views = 1,
          String? note,
          String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/student-desk/view-requests/$id/decide',
            data: {
              'decision': grant ? 'grant' : 'reject',
              if (grant) 'views': views,
              if (note != null) 'note': note,
            },
            options: _opts(TeamModule.desk, key: key));
        bodyOf(res);
      });

  // ── placement (#56) ─────────────────────────────────────────────────────

  Future<List<PlacementFollowup>> companyFollowups(
          {String tab = 'today'}) =>
      guard(() async {
        final res = await _dio.get<Object?>(
            '/team/placement/company-followups',
            queryParameters: {'tab': tab},
            options: _opts(TeamModule.placement));
        final body = _map(bodyOf(res));
        return [
          for (final r in (body['rows'] as List? ?? const []))
            if (PlacementFollowup.tryParse(r) case final row?) row,
        ];
      });

  Future<String> revealCompany(String entryId, {String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/team/placement/company-followups/$entryId/reveal',
            options: _opts(TeamModule.placement, key: key));
        final phone = _map(bodyOf(res))['phone'];
        if (phone is! String || phone.isEmpty) throw const ParseFailure();
        return phone;
      });

  Future<void> recordCompanyCall(String entryId,
          {required String outcome,
          required String status,
          String? inProgressState,
          String? nextFollowUpOn,
          String? remark,
          String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/team/placement/company-followups/$entryId/calls',
            data: {
              'outcome': outcome,
              'status': status,
              if (inProgressState != null) 'in_progress_state': inProgressState,
              if (nextFollowUpOn != null) 'next_follow_up_on': nextFollowUpOn,
              if (remark != null) 'remark': remark,
            },
            options: _opts(TeamModule.placement, key: key));
        bodyOf(res);
      });

  Future<List<PlacementVerification>> verifications(
          {String status = 'pending'}) =>
      guard(() async {
        final res = await _dio.get<Object?>('/team/placement/verifications',
            queryParameters: {'status': status},
            options: _opts(TeamModule.placement));
        final body = _map(bodyOf(res));
        return [
          for (final r in (body['rows'] as List? ?? const []))
            if (PlacementVerification.tryParse(r) case final row?) row,
        ];
      });

  Future<void> placementCall(String id,
          {required String kind,
          required String outcome,
          String? note,
          String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/team/placement/verifications/$id/calls',
            data: {
              'kind': kind,
              'outcome': outcome,
              if (note != null) 'note': note,
            },
            options: _opts(TeamModule.placement, key: key));
        bodyOf(res);
      });

  Future<Map<String, dynamic>> decidePlacement(String id,
          {required bool approve, required String note, String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/team/placement/verifications/$id/decide',
            data: {'decision': approve ? 'approve' : 'reject', 'note': note},
            options: _opts(TeamModule.placement, key: key));
        return _map(bodyOf(res));
      });

  // ── complaints (#58) ────────────────────────────────────────────────────

  Future<List<ComplaintRow>> complaints({String filter = 'open'}) =>
      guard(() async {
        final res = await _dio.get<Object?>('/student-desk/complaints',
            queryParameters: {'filter': filter},
            options: _opts(TeamModule.complaints));
        final body = _map(bodyOf(res));
        return [
          for (final c in (body['complaints'] as List? ?? const []))
            if (ComplaintRow.tryParse(c) case final row?) row,
        ];
      });

  Future<ComplaintThread> complaint(String id) => guard(() async {
        final res = await _dio.get<Object?>('/student-desk/complaints/$id',
            options: _opts(TeamModule.complaints));
        final thread = ComplaintThread.fromJson(_map(bodyOf(res)));
        if (thread == null) throw const ParseFailure();
        return thread;
      });

  Future<void> replyComplaint(String id, String body, {String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/student-desk/complaints/$id/messages',
            data: {'body': body},
            options: _opts(TeamModule.complaints, key: key));
        bodyOf(res);
      });

  Future<void> setComplaintStatus(String id,
          {required String status, String? note, String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/student-desk/complaints/$id/status',
            data: {
              'status': status,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            },
            options: _opts(TeamModule.complaints, key: key));
        bodyOf(res);
      });

  // ── moderation (#58) ────────────────────────────────────────────────────

  Future<List<ModerationReport>> moderationReports() => guard(() async {
        final res = await _dio.get<Object?>('/student-desk/community/reports',
            options: _opts(TeamModule.moderation));
        final body = _map(bodyOf(res));
        return [
          for (final r in (body['reports'] as List? ?? const []))
            if (ModerationReport.tryParse(r) case final report?) report,
        ];
      });

  Future<void> hidePost(String id, String reason, {String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/student-desk/community/posts/$id/hide',
            data: {'reason': reason},
            options: _opts(TeamModule.moderation, key: key));
        bodyOf(res);
      });

  Future<void> restorePost(String id, {String? note, String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/student-desk/community/posts/$id/restore',
            data: {if (note != null) 'note': note},
            options: _opts(TeamModule.moderation, key: key));
        bodyOf(res);
      });

  Future<void> warnMember(String id,
          {required String reason, String? postId, String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
            '/student-desk/community/members/$id/warn',
            data: {
              'reason': reason,
              if (postId != null) 'post_id': postId,
            },
            options: _opts(TeamModule.moderation, key: key));
        bodyOf(res);
      });

  // ── test marks (#57) ────────────────────────────────────────────────────

  Future<List<BatchTest>> batchTests(String batchId) => guard(() async {
        final res = await _dio.get<Object?>('/test-scores',
            queryParameters: {'batch_id': batchId},
            options: _opts(TeamModule.social));
        final body = bodyOf(res);
        final rows = body is Map
            ? (body['tests'] ?? body['rows'] ?? const [])
            : body;
        return [
          if (rows is List)
            for (final t in rows)
              if (BatchTest.tryParse(t) case final test?) test,
        ];
      });

  Future<void> saveTest(Map<String, dynamic> body, {String? key}) =>
      guard(() async {
        final res = await _dio.post<Object?>('/test-scores',
            data: body, options: _opts(null, key: key));
        bodyOf(res);
      });
}

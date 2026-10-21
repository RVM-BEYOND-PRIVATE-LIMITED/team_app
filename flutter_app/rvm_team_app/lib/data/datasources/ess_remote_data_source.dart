import 'package:core_network/core_network.dart';
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

  Map<String, dynamic> _body(Response<dynamic> res) {
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw failureFromResponse(status, res.data);
    }
    return (res.data as Map).cast<String, dynamic>();
  }

  Map<String, dynamic> _obj(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : const {};

  List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) parse) =>
      raw is List
          ? raw
              .whereType<Map>()
              .map((e) => parse(e.cast<String, dynamic>()))
              .toList(growable: false)
          : <T>[];

  // ── health / identity ────────────────────────────────────────────────────

  Future<EssHealth> health() =>
      guard(() async => EssHealth.fromJson(_body(await _dio.get('/health'))));

  Future<EssMe> me() =>
      guard(() async => EssMe.fromJson(_body(await _dio.get('/me'))));

  Future<EssCapabilities> capabilities() => guard(() async =>
      EssCapabilities.fromJson(_body(await _dio.get('/me/capabilities'))));

  // ── kept sign-in (A3) ────────────────────────────────────────────────────

  Future<KeptSession> keepSignIn(
          {required String installId, String? deviceLabel}) =>
      guard(() async {
        final res = await _dio.post('/session', data: {
          'install_id': installId,
          if (deviceLabel != null && deviceLabel.trim().isNotEmpty)
            'device_label': deviceLabel.trim(),
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
            _body(await _dio
                .post('/sign-in/resolve', data: {'identifier': identifier})),
          ));

  // ── personal details (E9) ────────────────────────────────────────────────

  Future<PersonalDetails> readMyPersonal() =>
      guard(() async => PersonalDetails.fromJson(
            _obj(_body(await _dio.get('/me/personal'))['personal']),
          ));

  Future<PersonalDetails> updateMyPersonal(Map<String, dynamic> patch) =>
      guard(() async => PersonalDetails.fromJson(_obj(
          _body(await _dio.put('/me/personal', data: patch))['personal'])));

  Future<({EmployeeCard employee, PersonalDetails personal})> employeePersonal(
          String employeeId) =>
      guard(() async {
        final data =
            _body(await _dio.get('/hr/employees/$employeeId/personal'));
        return (
          employee: EmployeeCard.fromJson(_obj(data['employee'])),
          personal: PersonalDetails.fromJson(_obj(data['personal'])),
        );
      });

  Future<({EmployeeCard employee, PersonalDetails personal})>
      updateEmployeePersonal(String employeeId, Map<String, dynamic> patch) =>
          guard(() async {
            final data = _body(await _dio
                .put('/hr/employees/$employeeId/personal', data: patch));
            return (
              employee: EmployeeCard.fromJson(_obj(data['employee'])),
              personal: PersonalDetails.fromJson(_obj(data['personal'])),
            );
          });

  // ── data requests (A8) ───────────────────────────────────────────────────

  Future<EssDataRequest> createMyDataRequest(
          {required String kind, required String details}) =>
      guard(() async => EssDataRequest.fromJson(_obj(
            _body(await _dio.post('/me/data-requests',
                data: {'kind': kind, 'details': details}))['request'],
          )));

  Future<List<EssDataRequest>> myDataRequests() => guard(() async => _list(
        _body(await _dio.get('/me/data-requests'))['requests'],
        EssDataRequest.fromJson,
      ));

  Future<({List<EssDataRequest> requests, bool truncated})> hrDataRequests(
          {String status = 'open'}) =>
      guard(() async {
        final data = _body(await _dio
            .get('/hr/data-requests', queryParameters: {'status': status}));
        return (
          requests: _list(data['requests'], EssDataRequest.fromJson),
          truncated: data['truncated'] == true
        );
      });

  Future<EssDataRequest> resolveDataRequest(String id,
          {required String status, String? note}) =>
      guard(() async => EssDataRequest.fromJson(_obj(
            _body(await _dio.patch('/hr/data-requests/$id', data: {
              'status': status,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            }))['request'],
          )));

  // ── attendance day + mock location (B1, B14) ─────────────────────────────

  Future<AttendanceDay> attendanceDay(String date) =>
      guard(() async => AttendanceDay.fromJson(
            _body(await _dio
                .get('/attendance/day', queryParameters: {'date': date})),
          ));

  Future<MockLocationReport> reportMockLocation(Map<String, dynamic> body) =>
      guard(() async => MockLocationReport.fromJson(_obj(
          _body(await _dio.post('/attendance/mock-location', data: body))[
              'report'])));

  Future<({List<MockLocationReport> reports, bool truncated})>
      mockLocationReports({
    String? from,
    String? to,
    String? branchId,
  }) =>
          guard(() async {
            final data = _body(
                await _dio.get('/hr/mock-location-reports', queryParameters: {
              if (from != null) 'from': from,
              if (to != null) 'to': to,
              if (branchId != null) 'branch_id': branchId,
            }));
            return (
              reports: _list(data['reports'], MockLocationReport.fromJson),
              truncated: data['truncated'] == true
            );
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
        return (
          devices: _list(data['devices'], RegisteredPhone.fromJson),
          truncated: data['truncated'] == true
        );
      });

  Future<int> resetDevices(Map<String, dynamic> body) => guard(() async {
        final data = _body(await _dio.post('/hr/devices/reset', data: body));
        return (data['reset'] as num?)?.toInt() ?? 0;
      });

  // ── 1E: profile, org, directory, team, praise ────────────────────────────

  Future<MyProfile> myProfile() => guard(
      () async => MyProfile.fromJson(_body(await _dio.get('/me/profile'))));

  Future<OrgView> myOrg() =>
      guard(() async => OrgView.fromJson(_body(await _dio.get('/me/org'))));

  Future<DirectoryPage> directory(
          {String? query, String? branchId, String? departmentId}) =>
      guard(() async => DirectoryPage.fromJson(
              _body(await _dio.get('/directory', queryParameters: {
            if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
            if (branchId != null) 'branch_id': branchId,
            if (departmentId != null) 'department_id': departmentId,
          }))));

  Future<TeamTodayView> teamToday({String filter = 'all'}) =>
      guard(() async => TeamTodayView.fromJson(_body(
          await _dio.get('/team/today', queryParameters: {'filter': filter}))));

  Future<TeamOffWeek> teamOffThisWeek() => guard(() async =>
      TeamOffWeek.fromJson(_body(await _dio.get('/team/off-this-week'))));

  Future<PraisePage> myPraise({String? employeeId}) => guard(() async =>
      PraisePage.fromJson(_body(await _dio.get('/me/praise', queryParameters: {
        if (employeeId != null) 'employee_id': employeeId
      }))));

  // ── 1C: requests, leave, balances, approvals ─────────────────────────────

  Future<EssRequest> createAttendanceRequest({
    required String type,
    required String day,
    required String reason,
    String? place,
    String? fixIn,
    String? fixOut,
    int? minutes,
  }) =>
      guard(() async => EssRequest.fromJson(
              _obj(_body(await _dio.post('/attendance-requests', data: {
            'type': type,
            'day': day,
            'reason': reason,
            if (place != null) 'place': place,
            if (fixIn != null) 'fix_in': fixIn,
            if (fixOut != null) 'fix_out': fixOut,
            if (minutes != null) 'minutes': minutes,
          }))['request'])));

  Future<List<EssRequest>> myAttendanceRequests() => guard(() async => _list(
      _body(await _dio.get('/attendance-requests'))['requests'],
      EssRequest.fromJson));

  Future<EssRequest> withdrawAttendanceRequest(String id) =>
      guard(() async => EssRequest.fromJson(_obj(_body(
          await _dio.post('/attendance-requests/$id/withdraw'))['request'])));

  Future<EssRequest> createLeaveRequest(
          {required String type,
          required String day,
          required String reason}) =>
      guard(() async => EssRequest.fromJson(
              _obj(_body(await _dio.post('/leave-requests', data: {
            'type': type,
            'day': day,
            'reason': reason,
          }))['request'])));

  Future<List<EssRequest>> myLeaveRequests() => guard(() async => _list(
      _body(await _dio.get('/leave-requests'))['requests'],
      EssRequest.fromJson));

  Future<EssRequest> withdrawLeaveRequest(String id) =>
      guard(() async => EssRequest.fromJson(_obj(
          _body(await _dio.post('/leave-requests/$id/withdraw'))['request'])));

  Future<LeaveBalances> leaveBalances({String? month}) => guard(() async =>
      LeaveBalances.fromJson(_body(await _dio.get('/leave/balances',
          queryParameters: {if (month != null) 'month': month}))));

  Future<ApprovalInbox> approvals({String status = 'pending'}) =>
      guard(() async => ApprovalInbox.fromJson(_body(
          await _dio.get('/approvals', queryParameters: {'status': status}))));

  Future<EssRequest> decideRequest({
    required String family,
    required String id,
    required String decision,
    String? note,
  }) =>
      guard(() async => EssRequest.fromJson(_obj(
              _body(await _dio.post('/approvals/$family/$id/decide', data: {
            'decision': decision,
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }))['request'])));

  Future<void> archiveRequest({required String family, required String id}) =>
      guard(() async => _dio.post('/approvals/$family/$id/archive'));

  // ── 1D: notifications ────────────────────────────────────────────────────

  Future<NotificationPage> notifications() => guard(() async =>
      NotificationPage.fromJson(_body(await _dio.get('/notifications'))));

  Future<void> readNotification(String id) =>
      guard(() async => _dio.post('/notifications/$id/read'));

  Future<int> readAllNotifications() => guard(() async {
        final data = _body(await _dio.post('/notifications/read-all'));
        return (data['marked'] as num?)?.toInt() ?? 0;
      });

  Future<NotificationSettings> notificationSettings() =>
      guard(() async => NotificationSettings.fromJson(
          _body(await _dio.get('/notifications/settings'))));

  Future<NotificationSettings> saveNotificationSettings(
          List<String> disabledCategories) =>
      guard(() async => NotificationSettings.fromJson(_body(await _dio.put(
          '/notifications/settings',
          data: {'disabled_categories': disabledCategories}))));

  // ── 2A: the Wall ─────────────────────────────────────────────────────────

  /// Wall reads that answer `(data, failure)` instead of throwing. The Wall is a
  /// whole tab: a server that has not had the wall tables migrated yet (503
  /// MODULE_NOT_INSTALLED) must leave the person on a clear, retryable screen,
  /// not stop the debugger on a handled exception.
  Future<({WallSettings? data, Failure? failure})> wallSettingsSafe() =>
      _soft(() => _dio.get('/wall/settings'), WallSettings.fromJson);

  Future<({WallFeed? data, Failure? failure})> wallFeedSafe(
          {String? scope, String? before}) =>
      _soft(
        () => _dio.get('/wall/posts', queryParameters: {
          if (scope != null) 'scope': scope,
          if (before != null) 'before': before,
        }),
        (body) => WallFeed(
            posts: _list(body['posts'], WallPost.fromJson),
            truncated: body['truncated'] == true),
      );

  Future<({List<WallAnnouncement>? data, Failure? failure})>
      wallAnnouncementsSafe() => _soft(
            () => _dio.get('/wall/announcements'),
            (body) => _list(body['announcements'], WallAnnouncement.fromJson),
          );

  Future<({WallCelebrations? data, Failure? failure})> wallCelebrationsSafe() =>
      _soft(() => _dio.get('/wall/celebrations'), WallCelebrations.fromJson);

  Future<({T? data, Failure? failure})> _soft<T>(
    Future<Response<dynamic>> Function() request,
    T Function(Map<String, dynamic> body) parse,
  ) async {
    try {
      final res = await request();
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        return (data: null, failure: failureFromResponse(status, res.data));
      }
      final raw = res.data;
      if (raw is! Map) return (data: null, failure: const ParseFailure());
      return (data: parse(raw.cast<String, dynamic>()), failure: null);
    } on DioException catch (e) {
      return (data: null, failure: e.asFailure);
    } on Object {
      return (data: null, failure: const ParseFailure());
    }
  }

  Future<WallSettings> wallSettings() => guard(() async =>
      WallSettings.fromJson(_body(await _dio.get('/wall/settings'))));

  Future<WallFeed> wallFeed({String? scope, String? before}) => guard(() async {
        final data = _body(await _dio.get('/wall/posts', queryParameters: {
          if (scope != null) 'scope': scope,
          if (before != null) 'before': before,
        }));
        return WallFeed(
            posts: _list(data['posts'], WallPost.fromJson),
            truncated: data['truncated'] == true);
      });

  Future<WallPostDetail> wallPost(String id) => guard(() async =>
      WallPostDetail.fromJson(_body(await _dio.get('/wall/posts/$id'))));

  Future<WallPost> createWallPost({
    required String body,
    String kind = 'post',
    String? scope,
    Map<String, dynamic>? poll,
    List<Map<String, dynamic>>? attachments,
  }) =>
      guard(() async =>
          WallPost.fromJson(_obj(_body(await _dio.post('/wall/posts', data: {
            'kind': kind,
            'body': body,
            if (scope != null) 'scope': scope,
            if (poll != null) 'poll': poll,
            if (attachments != null && attachments.isNotEmpty)
              'attachments': attachments,
          }))['post'])));

  Future<List<WallReactionGroup>> postReactions(String id) =>
      guard(() async => _list(
            _body(await _dio.get('/wall/posts/$id/reactions'))['reactions'],
            WallReactionGroup.fromJson,
          ));

  Future<List<WallReactionGroup>> commentReactions(String id) =>
      guard(() async => _list(
            _body(await _dio.get('/wall/comments/$id/reactions'))['reactions'],
            WallReactionGroup.fromJson,
          ));

  Future<void> addPollOption(String id, String label) => guard(
      () async => _dio.post('/wall/polls/$id/options', data: {'label': label}));

  Future<void> closePoll(String id) =>
      guard(() async => _dio.post('/wall/polls/$id/close'));

  Future<String?> putMyPhoto(
          {required String base64, required String contentType}) =>
      guard(() async {
        final data = _body(await _dio.put('/me/photo',
            data: {'photo_base64': base64, 'content_type': contentType}));
        return _obj(data['employee'])['photo_url']?.toString();
      });

  Future<void> registerPushDevice(
          {required String token, String? deviceLabel, String? installId}) =>
      guard(() async => _dio.post('/push-devices', data: {
            'token': token,
            if (deviceLabel != null && deviceLabel.isNotEmpty)
              'device_label': deviceLabel,
            if (installId != null && installId.isNotEmpty)
              'install_id': installId,
          }));

  Future<void> revokePushDevice(String id) =>
      guard(() async => _dio.delete('/push-devices/$id'));

  Future<void> deleteWallPost(String id) =>
      guard(() async => _dio.delete('/wall/posts/$id'));

  Future<({WallReactionCounts counts, String? myReaction})> reactToPost(
          String id, String reaction) =>
      guard(() async {
        final data = _body(await _dio
            .put('/wall/posts/$id/reaction', data: {'reaction': reaction}));
        return (
          counts: WallReactionCounts.fromJson(_mapOf(data['counts'])),
          myReaction: data['my_reaction']?.toString()
        );
      });

  Future<({WallReactionCounts counts, String? myReaction})> unreactToPost(
          String id) =>
      guard(() async {
        final data = _body(await _dio.delete('/wall/posts/$id/reaction'));
        return (
          counts: WallReactionCounts.fromJson(_mapOf(data['counts'])),
          myReaction: null
        );
      });

  Future<WallComment> addWallComment(
          {required String postId, required String body, String? parentId}) =>
      guard(() async => WallComment.fromJson(
              _obj(_body(await _dio.post('/wall/posts/$postId/comments', data: {
            'body': body,
            if (parentId != null) 'parent_id': parentId,
          }))['comment'])));

  Future<WallPost> createPraise({
    required String employeeId,
    required String badge,
    required String reason,
    String scope = 'org',
    List<Map<String, dynamic>>? attachments,
  }) =>
      guard(() async =>
          WallPost.fromJson(_obj(_body(await _dio.post('/wall/praise', data: {
            'employee_id': employeeId,
            'badge': badge,
            'reason': reason,
            'scope': scope,
            if (attachments != null && attachments.isNotEmpty)
              'attachments': attachments,
          }))['post'])));

  Future<List<WallAnnouncement>> wallAnnouncements() => guard(() async => _list(
        _body(await _dio.get('/wall/announcements'))['announcements'],
        WallAnnouncement.fromJson,
      ));

  Future<void> readAnnouncement(String id) =>
      guard(() async => _dio.post('/wall/announcements/$id/read'));

  Future<void> ackAnnouncement(String id) =>
      guard(() async => _dio.post('/wall/announcements/$id/ack'));

  Future<WallCelebrations> wallCelebrations() => guard(() async =>
      WallCelebrations.fromJson(_body(await _dio.get('/wall/celebrations'))));

  Future<void> sendWish(
          {required String employeeId,
          required String occasion,
          required String body}) =>
      guard(() async => _dio.post('/wall/wishes', data: {
            'employee_id': employeeId,
            'occasion': occasion,
            'body': body,
          }));

  Future<void> votePoll(
          {required String pollId, required List<String> optionIds}) =>
      guard(() async => _dio
          .post('/wall/polls/$pollId/vote', data: {'option_ids': optionIds}));

  // ── 2B: Helpdesk ─────────────────────────────────────────────────────────

  Future<HelpdeskSettings> helpdeskCategories() => guard(() async =>
      HelpdeskSettings.fromJson(_body(await _dio.get('/helpdesk/categories'))));

  Future<List<HelpdeskTicket>> myTickets({String? status}) =>
      guard(() async => _list(
            _body(await _dio.get('/helpdesk/tickets', queryParameters: {
              if (status != null) 'status': status
            }))['tickets'],
            HelpdeskTicket.fromJson,
          ));

  Future<HelpdeskTicket> raiseTicket({
    required String category,
    required String subject,
    required String body,
    bool anonymous = false,
  }) =>
      guard(() async => HelpdeskTicket.fromJson(
              _obj(_body(await _dio.post('/helpdesk/tickets', data: {
            'category': category,
            'subject': subject,
            'body': body,
            'anonymous': anonymous,
          }))['ticket'])));

  Future<HelpdeskTicketDetail> ticket(String id) =>
      guard(() async => HelpdeskTicketDetail.fromJson(
          _body(await _dio.get('/helpdesk/tickets/$id'))));

  Future<HelpdeskMessage> addTicketComment(
          {required String id, required String body}) =>
      guard(() async => HelpdeskMessage.fromJson(_obj(_body(await _dio.post(
          '/helpdesk/tickets/$id/comments',
          data: {'body': body}))['message'])));

  Future<HelpdeskTicket> ticketAction(String id, String action,
          {Map<String, dynamic>? data}) =>
      guard(() async => HelpdeskTicket.fromJson(_obj(_body(await _dio.post(
          '/helpdesk/tickets/$id/$action',
          data: data ?? const {}))['ticket'])));

  Future<HelpdeskTicket> assignTicket(
          {required String id, required String employeeId, String? note}) =>
      guard(() async => HelpdeskTicket.fromJson(
              _obj(_body(await _dio.post('/helpdesk/tickets/$id/assign', data: {
            'employee_id': employeeId,
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }))['ticket'])));

  Future<HelpdeskQueue> helpdeskQueue({String? status, String? category}) =>
      guard(() async => HelpdeskQueue.fromJson(
              _body(await _dio.get('/helpdesk/queue', queryParameters: {
            if (status != null) 'status': status,
            if (category != null) 'category': category,
          }))));

  // ── 2C: documents, change requests, bank details, ID card ────────────────

  Future<DocumentPage> myDocuments() => guard(() async =>
      DocumentPage.fromJson(_body(await _dio.get('/me/documents'))));

  Future<EssDocument> uploadDocument({
    required String docType,
    required String fileName,
    required String contentType,
    required String base64,
    String? remark,
  }) =>
      guard(() async => EssDocument.fromJson(
              _obj(_body(await _dio.post('/me/documents', data: {
            'doc_type': docType,
            'file_name': fileName,
            'content_type': contentType,
            'data_base64': base64,
            if (remark != null && remark.trim().isNotEmpty)
              'remark': remark.trim(),
          }))['document'])));

  Future<String?> documentFileUrl(String id) => guard(() async {
        final data = _body(await _dio.get('/me/documents/$id/file'));
        return _obj(data['file'])['url']?.toString();
      });

  Future<List<ChangeRequest>> myChangeRequests() => guard(() async => _list(
      _body(await _dio.get('/me/change-requests'))['requests'],
      ChangeRequest.fromJson));

  Future<ChangeRequest> createChangeRequest({
    required String field,
    String? oldValue,
    required String newValue,
    required String reason,
  }) =>
      guard(() async => ChangeRequest.fromJson(
              _obj(_body(await _dio.post('/me/change-requests', data: {
            'field': field,
            if (oldValue != null) 'old_value': oldValue,
            'new_value': newValue,
            'reason': reason,
          }))['request'])));

  Future<BankDetails?> myBankDetails() => guard(() async {
        final data = _body(await _dio.get('/me/bank-details'));
        final bank = _mapOf(data['bank_details']);
        return bank.isEmpty ? null : BankDetails.fromJson(bank);
      });

  Future<BankDetails> saveBankDetails({
    required String bankName,
    String? branchName,
    required String accountNumber,
    required String ifscCode,
    String? upiId,
    required String consentName,
  }) =>
      guard(() async => BankDetails.fromJson(
              _obj(_body(await _dio.put('/me/bank-details', data: {
            'bank_name': bankName,
            if (branchName != null) 'branch_name': branchName,
            'account_number': accountNumber,
            'ifsc_code': ifscCode,
            if (upiId != null) 'upi_id': upiId,
            'consent': true,
            'consent_name': consentName,
          }))['bank_details'])));

  Future<IdCard> myIdCard() => guard(() async =>
      IdCard.fromJson(_obj(_body(await _dio.get('/me/id-card'))['card'])));

  Future<WallPost> editWallPost(String id, String body) =>
      guard(() async => WallPost.fromJson(_obj(_body(
          await _dio.patch('/wall/posts/$id', data: {'body': body}))['post'])));

  Future<void> deleteWallComment(String id) =>
      guard(() async => _dio.delete('/wall/comments/$id'));

  Future<WallComment> editWallComment(String id, String body) =>
      guard(() async => WallComment.fromJson(_obj(
          _body(await _dio.patch('/wall/comments/$id', data: {'body': body}))[
              'comment'])));

  Future<({WallReactionCounts counts, String? myReaction})> reactToComment(
          String id, String reaction) =>
      guard(() async {
        final data = _body(await _dio
            .put('/wall/comments/$id/reaction', data: {'reaction': reaction}));
        return (
          counts: WallReactionCounts.fromJson(_mapOf(data['counts'])),
          myReaction: data['my_reaction']?.toString()
        );
      });

  Future<({WallReactionCounts counts, String? myReaction})> unreactToComment(
          String id) =>
      guard(() async {
        final data = _body(await _dio.delete('/wall/comments/$id/reaction'));
        return (
          counts: WallReactionCounts.fromJson(_mapOf(data['counts'])),
          myReaction: null
        );
      });

  Future<void> reportPost(String id,
          {required String reason, String? detail}) =>
      guard(() async => _dio.post('/wall/posts/$id/reports', data: {
            'reason': reason,
            if (detail != null && detail.trim().isNotEmpty)
              'detail': detail.trim(),
          }));

  Future<void> reportComment(String id,
          {required String reason, String? detail}) =>
      guard(() async => _dio.post('/wall/comments/$id/reports', data: {
            'reason': reason,
            if (detail != null && detail.trim().isNotEmpty)
              'detail': detail.trim(),
          }));

  Future<void> withdrawPollVote(String id) =>
      guard(() async => _dio.delete('/wall/polls/$id/vote'));

  Future<bool> celebrationOptout() => guard(() async {
        final data = _body(await _dio.get('/me/celebration-optout'));
        return _obj(data['celebrations'])['hidden'] == true;
      });

  Future<void> setCelebrationOptout(bool hidden) => guard(
      () async => _dio.put('/me/celebration-optout', data: {'hidden': hidden}));

  // ── 2D: leaders, faculty day, approval chain ─────────────────────────────

  Future<LeadersOverview> leadersOverview() => guard(() async =>
      LeadersOverview.fromJson(_body(await _dio.get('/leaders/overview'))));

  Future<FacultyDay> facultyDay({String? date}) => guard(() async =>
      FacultyDay.fromJson(_body(await _dio.get('/me/faculty-day',
          queryParameters: {if (date != null) 'date': date}))));

  Future<ApprovalChain> approvalChain(String family, String id) =>
      guard(() async => ApprovalChain.fromJson(
          _body(await _dio.get('/approvals/$family/$id/chain'))));

  // ── HR desk ──────────────────────────────────────────────────────────────

  Future<List<RequestLimit>> requestLimits() => guard(() async => _list(
      _body(await _dio.get('/hr/request-limits'))['limits'],
      RequestLimit.fromJson));

  Future<void> setRequestLimit(String type, {int? count, int? minutes}) =>
      guard(() async => _dio.put('/hr/request-limits/$type', data: {
            if (count != null) 'limit_count': count,
            if (minutes != null) 'limit_minutes': minutes,
          }));

  Future<EssRequest> cancelRequest(String family, String id, String reason) =>
      guard(() async {
        final path = family == 'leave'
            ? '/hr/leave-requests/$id/cancel'
            : '/hr/attendance-requests/$id/cancel';
        return EssRequest.fromJson(_obj(
            _body(await _dio.post(path, data: {'reason': reason}))['request']));
      });

  Future<List<ChangeRequest>> hrChangeRequests() => guard(() async => _list(
      _body(await _dio.get('/hr/change-requests'))['requests'],
      ChangeRequest.fromJson));

  Future<ChangeRequest> decideChangeRequest(String id,
          {required bool approve, String? note}) =>
      guard(() async => ChangeRequest.fromJson(_obj(
              _body(await _dio.post('/hr/change-requests/$id/decide', data: {
            'decision': approve ? 'approved' : 'rejected',
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }))['request'])));

  Future<DocumentPage> hrEmployeeDocuments(String employeeId) =>
      guard(() async => DocumentPage.fromJson(
          _body(await _dio.get('/hr/employees/$employeeId/documents'))));

  Future<String?> hrDocumentFileUrl(String employeeId, String documentId) =>
      guard(() async {
        final data = _body(await _dio
            .get('/hr/employees/$employeeId/documents/$documentId/file'));
        return _obj(data['file'])['url']?.toString();
      });

  Future<EssDocument> verifyDocument(String employeeId, String documentId) =>
      guard(() async => EssDocument.fromJson(_obj(_body(await _dio
              .post('/hr/employees/$employeeId/documents/$documentId/verify'))[
          'document'])));

  Future<EssDocument> rejectDocument(
          String employeeId, String documentId, String reason) =>
      guard(() async => EssDocument.fromJson(_obj(_body(await _dio.post(
          '/hr/employees/$employeeId/documents/$documentId/reject',
          data: {'reason': reason}))['document'])));

  Future<void> deleteDocument(String employeeId, String documentId) =>
      guard(() async =>
          _dio.delete('/hr/employees/$employeeId/documents/$documentId'));

  Future<BankDetails?> hrEmployeeBank(String employeeId) => guard(() async {
        final data =
            _body(await _dio.get('/hr/employees/$employeeId/bank-details'));
        final bank = _mapOf(data['bank_details']);
        return bank.isEmpty ? null : BankDetails.fromJson(bank);
      });

  // ── Wall moderation and announcements (HR) ───────────────────────────────

  Future<WallAnnouncement> createAnnouncement({
    required String title,
    required String body,
    bool needsAck = false,
    String? closesOn,
    bool pinned = false,
    List<String>? employeeIds,
    List<Map<String, dynamic>>? attachments,
    String? publishAt,
  }) =>
      guard(() async => WallAnnouncement.fromJson(
              _obj(_body(await _dio.post('/wall/announcements', data: {
            'title': title,
            'body': body,
            'audience': (employeeIds == null || employeeIds.isEmpty)
                ? {'all': true}
                : {'employee_ids': employeeIds},
            'needs_ack': needsAck,
            if (closesOn != null) 'closes_on': closesOn,
            'pinned': pinned,
            if (attachments != null && attachments.isNotEmpty)
              'attachments': attachments,
            if (publishAt != null) 'publish_at': publishAt,
          }))['announcement'])));

  Future<List<WallAnnouncement>> hrAnnouncements() => guard(() async => _list(
      _body(await _dio.get('/wall/hr/announcements'))['announcements'],
      WallAnnouncement.fromJson));

  Future<Map<String, int>> announcementCounts(String id) => guard(() async {
        final counts = _mapOf(
            _body(await _dio.get('/wall/announcements/$id/counts'))['counts']);
        return counts.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
      });

  Future<void> hidePost(String id, String reason) => guard(
      () async => _dio.post('/wall/posts/$id/hide', data: {'reason': reason}));

  Future<void> hideComment(String id, String reason) => guard(() async =>
      _dio.post('/wall/comments/$id/hide', data: {'reason': reason}));

  Future<List<WallReport>> wallReports({String status = 'open'}) =>
      guard(() async => _list(
          _body(await _dio.get('/wall/hr/reports',
              queryParameters: {'status': status}))['reports'],
          WallReport.fromJson));

  Future<void> resolveReport(String id, {required bool hidden, String? note}) =>
      guard(() async => _dio.post('/wall/hr/reports/$id/resolve', data: {
            'status': hidden ? 'hidden' : 'kept',
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }));

  Future<List<ModerationEntry>> moderationLog() => guard(() async => _list(
      _body(await _dio.get('/wall/hr/moderation-log'))['entries'],
      ModerationEntry.fromJson));

  Future<WallAnnouncement> editAnnouncement(String id,
          {required String title, required String body, bool? pinned}) =>
      guard(() async => WallAnnouncement.fromJson(
              _obj(_body(await _dio.patch('/wall/announcements/$id', data: {
            'title': title,
            'body': body,
            if (pinned != null) 'pinned': pinned,
          }))['announcement'])));

  Future<void> deleteAnnouncement(String id) =>
      guard(() async => _dio.delete('/wall/announcements/$id'));

  Future<void> unhidePost(String id) =>
      guard(() async => _dio.delete('/wall/posts/$id/hide'));

  Future<void> unhideComment(String id) =>
      guard(() async => _dio.delete('/wall/comments/$id/hide'));

  Map<String, dynamic> _mapOf(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : const {};
}

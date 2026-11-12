import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

import '../../domain/attendance_models.dart';
import '../../domain/ess_models.dart';
import '../dio_executor.dart';

/// The Scheduler's own punch path (`/api/hr/my-attendance`). The device cookie
/// (`rvm_att_dev`) and the mobile User-Agent are set on the Scheduler Dio, so
/// these calls carry them automatically (tasks B8/B13).
class MyAttendanceRemoteDataSource with DioExecutor {
  MyAttendanceRemoteDataSource(this._dio);

  final Dio _dio;

  /// Expected refusals on this path (a 409 cooldown, an already-punched-in
  /// state, a 403 device rule) are results the screen must render, not a
  /// DioException the debugger stops on. Returning them as a normal Response
  /// lets [DioExecutor.guard] turn them into the typed Failure the blocs
  /// already handle. 401 still throws so the bearer interceptor ends the
  /// session.
  Options _readOptions() => Options(
      validateStatus: (status) => status != null && status != 401);

  Future<MyAttendance> myAttendance({String? month}) async {
    final res = await guard<Response<dynamic>>(() => _dio.get(
          '/hr/my-attendance',
          queryParameters: {if (month != null) 'month': month},
          options: _readOptions(),
        ));
    return MyAttendance.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// The Home/schedule read without throwing for a 401/403/5xx. A portal
  /// token can be refused by the Scheduler's own employee link rules even
  /// though the ESS capabilities passed; that must render a card, not a
  /// DioException the debugger stops on.
  Future<({MyAttendance? data, Failure? failure})> myAttendanceSafe(
      {String? month}) async {
    try {
      final res = await _dio.get(
        '/hr/my-attendance',
        queryParameters: {if (month != null) 'month': month},
        options: Options(validateStatus: (_) => true),
      );
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        return (data: null, failure: failureFromResponse(status, res.data));
      }
      return (
        data: MyAttendance.fromJson((res.data as Map).cast<String, dynamic>()),
        failure: null,
      );
    } on DioException catch (e) {
      return (data: null, failure: Failure.fromDio(e));
    } catch (_) {
      return (
        data: null,
        failure: const UnknownFailure('Could not load your attendance.'),
      );
    }
  }

  Future<PunchChallenge> challenge() async {
    final res = await guard<Response<dynamic>>(
        () => _dio.get('/hr/my-attendance/challenge', options: _readOptions()));
    return PunchChallenge.fromJson(
        (res.data as Map).cast<String, dynamic>());
  }

  Future<PunchAccepted> punch({
    required String kind,
    required String nonce,
    required double latitude,
    required double longitude,
    required double accuracyM,
    DateTime? clientAt,
    String? note,
  }) async {
    final res = await guard<Response<dynamic>>(() =>
        _dio.post('/hr/my-attendance/punch', options: _readOptions(), data: {
          'kind': kind,
          'nonce': nonce,
          'latitude': latitude,
          'longitude': longitude,
          'accuracy_m': accuracyM,
          if (clientAt != null) 'client_at': clientAt.toIso8601String(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        }));
    return PunchAccepted.fromJson(
        (res.data as Map).cast<String, dynamic>());
  }

  Future<void> ping({
    required double latitude,
    required double longitude,
    required double accuracyM,
  }) async {
    await guard<Response<dynamic>>(() =>
        _dio.post('/hr/my-attendance/ping', options: _readOptions(), data: {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy_m': accuracyM,
        }));
  }

  Future<void> saveRemark({required String day, String? remarks}) async {
    await guard<Response<dynamic>>(() => _dio.put('/hr/my-attendance/remarks',
        options: _readOptions(), data: {'day': day, 'remarks': remarks}));
  }

  /// Set/replace the attendance password (first-time password / none yet). The
  /// reply's fresh 30-day token replaces the current session; every older
  /// session of this login stops working.
  Future<String> setAttendancePassword(String password) async {
    final res = await guard<Response<dynamic>>(() => _dio.post(
        '/hr/my-attendance/password',
        options: _readOptions(),
        data: {'password': password}));
    return ((res.data as Map).cast<String, dynamic>()['token']
            as String?) ??
        '';
  }

  // ── Leave (team_app #43) ─────────────────────────────────────────────────
  // From 23 Nov 2026 the Scheduler owns leave: the approver comes from HR's
  // mapping, CL is used automatically, and the rules live in the database.
  // Work from home stays on the ESS.

  static const _leave = '/hr/my-attendance/leave';

  Map<String, dynamic> _body(Response<dynamic> res) =>
      res.data is Map ? (res.data as Map).cast<String, dynamic>() : const {};

  EssRequest _request(Response<dynamic> res) => EssRequest.fromSchedulerLeave(
      (_body(res)['request'] as Map?)?.cast<String, dynamic>() ?? const {});

  /// Balances, my requests, the approvals waiting on me (oldest first),
  /// `earliest_self_day` and the short-notice message.
  Future<LeaveOverview> leaveOverview({String? month}) async {
    final res = await guard<Response<dynamic>>(() => _dio.get(_leave,
        queryParameters: {if (month != null) 'month': month},
        options: _readOptions()));
    return LeaveOverview.fromJson(_body(res));
  }

  /// Who a leave on these dates would go to ("Goes to X, then Y").
  Future<LeaveRoutePreview> leaveRoute({
    required String day,
    String? endDay,
    String portion = 'full',
  }) async {
    final res = await guard<Response<dynamic>>(() => _dio.get('$_leave/route',
        queryParameters: {
          'day': day,
          if (endDay != null) 'end_day': endDay,
          'portion': portion,
        },
        options: _readOptions()));
    return LeaveRoutePreview.fromJson(_body(res));
  }

  /// `type` is `cl` (CL where the person has it, else LWP) or `lwp`.
  /// `spoke_to_approver` must be the JSON boolean true.
  Future<EssRequest> createLeave({
    required String type,
    required String day,
    String? endDay,
    String portion = 'full',
    required String reason,
    required bool spokeToApprover,
  }) async {
    final res = await guard<Response<dynamic>>(() => _dio.post(_leave,
        options: _readOptions(),
        data: {
          'type': type,
          'day': day,
          if (endDay != null) 'end_day': endDay,
          'portion': portion,
          'reason': reason,
          'spoke_to_approver': spokeToApprover,
        }));
    return _request(res);
  }

  Future<EssRequest> withdrawLeave(String id) async {
    final res = await guard<Response<dynamic>>(() =>
        _dio.post('$_leave/$id/withdraw', options: _readOptions()));
    return _request(res);
  }

  /// Approve or reject. A teaching leave's 1st approver must send the
  /// substitute and the class timing (400 COVERAGE_REQUIRED otherwise).
  Future<LeaveDecision> decideLeave(
    String id, {
    required String decision,
    String? note,
    String? substituteFacultyId,
    String? classTiming,
  }) async {
    final res = await guard<Response<dynamic>>(
        () => _dio.post('$_leave/$id/decide', options: _readOptions(), data: {
              'decision': decision,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
              if (substituteFacultyId != null)
                'substitute_faculty_id': substituteFacultyId,
              if (classTiming != null) 'class_timing': classTiming,
            }));
    return LeaveDecision.fromJson(_body(res));
  }

  /// HR, HR Executive, CEO or super admin cancels an approved leave (reason
  /// 3 to 200 characters).
  Future<EssRequest> cancelLeave(String id, String reason) async {
    final res = await guard<Response<dynamic>>(() => _dio.post(
        '$_leave/$id/cancel',
        options: _readOptions(),
        data: {'reason': reason}));
    return _request(res);
  }

  /// Colleagues in the same branch and approver team off on the request's dates.
  Future<LeaveWhosOff> leaveWhosOff(String requestId) async {
    final res = await guard<Response<dynamic>>(() => _dio.get(
        '$_leave/whos-off',
        queryParameters: {'request_id': requestId},
        options: _readOptions()));
    return LeaveWhosOff.fromJson(_body(res));
  }

  /// Substitute faculty for a teaching leave's approver.
  Future<List<LeaveFacultyOption>> leaveFaculty({String? requestId}) async {
    final res = await guard<Response<dynamic>>(() => _dio.get(
        '$_leave/faculty',
        queryParameters: {if (requestId != null) 'request_id': requestId},
        options: _readOptions()));
    final rows = _body(res)['faculty'];
    return rows is List
        ? rows
            .whereType<Map>()
            .map((m) => LeaveFacultyOption.fromJson(m.cast<String, dynamic>()))
            .toList(growable: false)
        : const [];
  }
}

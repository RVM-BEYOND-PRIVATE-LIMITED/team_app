import 'package:core_network/core_network.dart';

import '../../domain/ess_models.dart';
import '../connectivity_guard.dart';
import '../datasources/my_attendance_remote_data_source.dart';

/// Casual leave and leave without pay on the Scheduler (team_app #43):
/// `/api/hr/my-attendance/leave*`, on the same session the punch path uses.
/// Work from home stays on the ESS ([EssRepository]).
class LeaveRepository with ConnectivityGuard {
  // The kept sign-in's 1-hour access token is renewed by the Scheduler
  // client itself (core_network SessionRotator, #50), so a leave screen that
  // calls the Scheduler alone no longer needs an ESS call to freshen it.
  LeaveRepository({
    required MyAttendanceRemoteDataSource remote,
    required this.connectivity,
  }) : _remote = remote;

  final MyAttendanceRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<void> _ready() => ensureOnline();

  Future<LeaveOverview> overview({String? month}) async {
    await _ready();
    return _remote.leaveOverview(month: month);
  }

  /// The overview without throwing, so one host failing does not blank the
  /// screens that also show ESS data.
  Future<({LeaveOverview? data, Failure? failure})> overviewSafe(
      {String? month}) async {
    try {
      return (data: await overview(month: month), failure: null);
    } on Failure catch (f) {
      return (data: null, failure: f);
    } catch (_) {
      return (
        data: null,
        failure: const UnknownFailure('Could not load your leave.'),
      );
    }
  }

  Future<LeaveRoutePreview> route({
    required String day,
    String? endDay,
    String portion = 'full',
  }) async {
    await _ready();
    return _remote.leaveRoute(day: day, endDay: endDay, portion: portion);
  }

  Future<EssRequest> create({
    required String type,
    required String day,
    String? endDay,
    String portion = 'full',
    required String reason,
    required bool spokeToApprover,
  }) async {
    await _ready();
    return _remote.createLeave(
      type: type,
      day: day,
      endDay: endDay,
      portion: portion,
      reason: reason,
      spokeToApprover: spokeToApprover,
    );
  }

  Future<EssRequest> withdraw(String id) async {
    await _ready();
    return _remote.withdrawLeave(id);
  }

  Future<LeaveDecision> decide(
    String id, {
    required String decision,
    String? note,
    String? substituteFacultyId,
    String? classTiming,
  }) async {
    await _ready();
    return _remote.decideLeave(
      id,
      decision: decision,
      note: note,
      substituteFacultyId: substituteFacultyId,
      classTiming: classTiming,
    );
  }

  Future<EssRequest> cancel(String id, String reason) async {
    await _ready();
    return _remote.cancelLeave(id, reason);
  }

  Future<LeaveWhosOff> whosOff(String requestId) async {
    await _ready();
    return _remote.leaveWhosOff(requestId);
  }

  Future<List<LeaveFacultyOption>> faculty({String? requestId}) async {
    await _ready();
    return _remote.leaveFaculty(requestId: requestId);
  }
}

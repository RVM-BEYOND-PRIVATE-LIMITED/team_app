import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../data/repositories/leave_repository.dart';
import '../../../domain/ess_models.dart';
import 'request_failure.dart';

/// C1–C5: my attendance and leave requests, and the month's balances.
///
/// Two hosts since team_app #43: casual leave and leave without pay live on
/// the Scheduler (`/hr/my-attendance/leave`); attendance requests and work from
/// home stay on the ESS.
sealed class RequestsEvent {
  const RequestsEvent();
}

class RequestsLoadRequested extends RequestsEvent {
  const RequestsLoadRequested();
}

class RequestsRefreshed extends RequestsEvent {
  const RequestsRefreshed();
}

/// Raise one request. `family` is attendance | leave; `type` is the family's own type.
class RequestCreateRequested extends RequestsEvent {
  const RequestCreateRequested({
    required this.family,
    required this.type,
    required this.day,
    this.endDay,
    this.portion = 'full',
    required this.reason,
    this.place,
    this.fixIn,
    this.fixOut,
    this.minutes,
    this.spokeToApprover = false,
  });
  final String family;
  final String type;
  final String day;
  final String? endDay;
  final String portion;
  final String reason;
  final String? place;
  final String? fixIn;
  final String? fixOut;
  final int? minutes;

  /// Leave only: "I have spoken to my approver about this leave" (#43).
  final bool spokeToApprover;
}

class RequestWithdrawRequested extends RequestsEvent {
  const RequestWithdrawRequested({required this.family, required this.id});
  final String family;
  final String id;
}

class RequestsState extends Equatable {
  const RequestsState({
    this.status = LoadStatus.initial,
    this.requests = const [],
    this.balances,
    this.failure,
    this.submitting = false,
    this.submitFailure,
    this.createdNonce = 0,
    this.leave,
    this.leaveFailure,
    this.essFailure,
  });

  final LoadStatus status;
  final List<EssRequest> requests;
  final LeaveBalances? balances;
  final Failure? failure;
  final bool submitting;
  final Failure? submitFailure;
  final int createdNonce;

  /// The Scheduler's leave overview: the rules the apply form needs
  /// (`earliest_self_day`, the short-notice message, my route).
  final LeaveOverview? leave;

  /// Set when the leave half could not load while the ESS half did.
  final Failure? leaveFailure;

  /// Set when the ESS half could not load while the leave half did.
  final Failure? essFailure;

  RequestsState copyWith({
    LoadStatus? status,
    bool? submitting,
    Failure? submitFailure,
    bool clearSubmitFailure = false,
    int? createdNonce,
  }) =>
      RequestsState(
        status: status ?? this.status,
        requests: requests,
        balances: balances,
        failure: failure,
        submitting: submitting ?? false,
        submitFailure:
            clearSubmitFailure ? null : (submitFailure ?? this.submitFailure),
        createdNonce: createdNonce ?? this.createdNonce,
        leave: leave,
        leaveFailure: leaveFailure,
        essFailure: essFailure,
      );

  @override
  List<Object?> get props => [
        status,
        requests,
        balances,
        failure,
        submitting,
        submitFailure,
        createdNonce,
        leave,
        leaveFailure,
        essFailure,
      ];
}

class RequestsBloc extends Bloc<RequestsEvent, RequestsState> {
  RequestsBloc(this._repo, this._leave) : super(const RequestsState()) {
    on<RequestsLoadRequested>((_, emit) => _load(emit));
    on<RequestsRefreshed>((_, emit) => _load(emit));
    on<RequestCreateRequested>(_onCreate);
    on<RequestWithdrawRequested>(_onWithdraw);
  }

  final EssRepository _repo;
  final LeaveRepository _leave;

  Future<void> _load(Emitter<RequestsState> emit) async {
    emit(RequestsState(
      status: LoadStatus.loading,
      requests: state.requests,
      balances: state.balances,
      createdNonce: state.createdNonce,
      leave: state.leave,
    ));
    // The ESS half first: its client rotates an expiring kept sign-in, which
    // the Scheduler half then uses.
    LeaveBalances? essBalances;
    var attendance = const <EssRequest>[];
    var wfh = const <EssRequest>[];
    Failure? essFailure;
    try {
      essBalances = await _repo.leaveBalances();
      attendance = await _repo.myAttendanceRequests();
      // Casual leave and LWP now come from the Scheduler; the ESS keeps work
      // from home. The table is shared, so keep only WFH here.
      wfh = (await _repo.myLeaveRequests())
          .where((r) => r.type == 'wfh')
          .toList(growable: false);
    } on Failure catch (f) {
      essFailure = f;
    }
    final leave = await _leave.overviewSafe();

    if (essFailure != null && leave.failure != null) {
      emit(RequestsState(
          status: LoadStatus.failure,
          failure: essFailure,
          createdNonce: state.createdNonce));
      return;
    }
    final overview = leave.data;
    final all = [...attendance, ...wfh, ...?overview?.requests]..sort((a, b) =>
        (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    emit(RequestsState(
      status: all.isEmpty ? LoadStatus.empty : LoadStatus.success,
      requests: all,
      balances: _mergeBalances(essBalances, overview),
      createdNonce: state.createdNonce,
      leave: overview,
      leaveFailure: leave.failure,
      essFailure: essFailure,
    ));
  }

  /// The quota card: Fix a day / On duty from the ESS, the leave rows from the
  /// Scheduler (which writes CL first and the rest as LWP).
  LeaveBalances? _mergeBalances(LeaveBalances? ess, LeaveOverview? leave) {
    if (ess == null && leave == null) return null;
    return LeaveBalances(
      month: ess?.month ?? leave!.month,
      types: [
        ...?ess?.types.where((t) => !t.type.startsWith('leave_')),
        ...?leave?.balances,
      ],
    );
  }

  Future<void> _onCreate(
      RequestCreateRequested e, Emitter<RequestsState> emit) async {
    emit(state.copyWith(submitting: true, clearSubmitFailure: true));
    try {
      final Failure? failure;
      if (e.family == 'leave' && e.type != 'wfh') {
        failure = await _createLeave(e);
      } else {
        final result = e.family == 'leave'
            ? await _repo.createLeaveRequestSafe(
                type: e.type,
                day: e.day,
                endDay: e.endDay,
                portion: e.portion,
                reason: e.reason)
            : await _repo.createAttendanceRequestSafe(
                type: e.type,
                day: e.day,
                reason: e.reason,
                place: e.place,
                fixIn: e.fixIn,
                fixOut: e.fixOut,
                minutes: e.minutes);
        failure = result.failure;
      }
      if (failure != null) {
        emit(state.copyWith(submitFailure: requestFailure(failure)));
        return;
      }
      emit(state.copyWith(createdNonce: state.createdNonce + 1));
      await _load(emit);
    } on Failure catch (f) {
      emit(state.copyWith(submitFailure: requestFailure(f)));
    } catch (e) {
      // A parse or plugin error must not leave the form saying it is submitting
      // (nor reach the debugger as an unhandled exception). Staff read the
      // friendly line; the raw exception stays in the log.
      emit(state.copyWith(
          submitFailure:
              const UnknownFailure('Could not send the request. Try again.')));
    }
  }

  /// Casual leave / LWP on the Scheduler. Returns the refusal, or null.
  Future<Failure?> _createLeave(RequestCreateRequested e) async {
    try {
      await _leave.create(
        type: e.type,
        day: e.day,
        endDay: e.endDay,
        portion: e.portion,
        reason: e.reason,
        spokeToApprover: e.spokeToApprover,
      );
      return null;
    } on Failure catch (f) {
      return f;
    }
  }

  Future<void> _onWithdraw(
      RequestWithdrawRequested e, Emitter<RequestsState> emit) async {
    try {
      final onScheduler =
          state.requests.any((r) => r.id == e.id && r.isSchedulerLeave);
      if (onScheduler) {
        await _leave.withdraw(e.id);
      } else if (e.family == 'leave') {
        await _repo.withdrawLeaveRequest(e.id);
      } else {
        await _repo.withdrawAttendanceRequest(e.id);
      }
      await _load(emit);
    } on Failure catch (f) {
      emit(state.copyWith(submitFailure: requestFailure(f)));
    }
  }
}

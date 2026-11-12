import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../data/repositories/leave_repository.dart';
import '../../../domain/ess_models.dart';
import 'request_failure.dart';

/// D1/H6: the approvals Inbox and the decision.
///
/// Two hosts since team_app #43: leave (CL/LWP) waits in the Scheduler's queue
/// (`/hr/my-attendance/leave`), attendance requests and work from home in the
/// ESS inbox. Both are merged into one list here.
sealed class ApprovalsEvent {
  const ApprovalsEvent();
}

class ApprovalsLoadRequested extends ApprovalsEvent {
  const ApprovalsLoadRequested();
}

class ApprovalsRefreshed extends ApprovalsEvent {
  const ApprovalsRefreshed();
}

class ApprovalsFiltered extends ApprovalsEvent {
  const ApprovalsFiltered(this.status);
  final String status;
}

class ApprovalDecided extends ApprovalsEvent {
  const ApprovalDecided({
    required this.family,
    required this.id,
    required this.decision,
    this.note,
    this.substituteFacultyId,
    this.classTiming,
  });
  final String family;
  final String id;
  final String decision; // approve | reject
  final String? note;

  /// Teaching leave at the Admin Manager stage: who covers the class and when.
  final String? substituteFacultyId;
  final String? classTiming;
}

class ApprovalArchived extends ApprovalsEvent {
  const ApprovalArchived({required this.family, required this.id});
  final String family;
  final String id;
}

class ApprovalsState extends Equatable {
  const ApprovalsState({
    this.status = LoadStatus.initial,
    this.filter = 'pending',
    this.inbox,
    this.failure,
    this.submitting = false,
    this.decidedNonce = 0,
    this.actionFailure,
    this.leave,
    this.lastOutcome,
    this.partialFailure,
  });

  final LoadStatus status;
  final String filter;
  final ApprovalInbox? inbox;
  final Failure? failure;
  final bool submitting;
  final int decidedNonce;
  final Failure? actionFailure;

  /// The Scheduler leave overview (`can_manage`, `approvals_count`), or null
  /// when that half could not load.
  final LeaveOverview? leave;

  /// The last Scheduler decision: `advanced` (sent on to the 2nd approver),
  /// `approved` or `rejected`.
  final String? lastOutcome;

  /// One half (ESS or Scheduler) could not load; the other half is shown.
  final Failure? partialFailure;

  ApprovalsState _with({
    bool submitting = false,
    Failure? actionFailure,
    int? decidedNonce,
    String? lastOutcome,
  }) =>
      ApprovalsState(
        status: status,
        filter: filter,
        inbox: inbox,
        failure: failure,
        submitting: submitting,
        decidedNonce: decidedNonce ?? this.decidedNonce,
        actionFailure: actionFailure,
        leave: leave,
        lastOutcome: lastOutcome ?? this.lastOutcome,
        partialFailure: partialFailure,
      );

  @override
  List<Object?> get props => [
        status,
        filter,
        inbox,
        failure,
        submitting,
        decidedNonce,
        actionFailure,
        leave,
        lastOutcome,
        partialFailure,
      ];
}

class ApprovalsBloc extends Bloc<ApprovalsEvent, ApprovalsState> {
  ApprovalsBloc(this._repo, this._leave) : super(const ApprovalsState()) {
    on<ApprovalsLoadRequested>((_, emit) => _load(emit, state.filter));
    on<ApprovalsRefreshed>((_, emit) => _load(emit, state.filter));
    on<ApprovalsFiltered>((e, emit) => _load(emit, e.status));
    on<ApprovalDecided>(_onDecide);
    on<ApprovalArchived>(_onArchive);
  }

  final EssRepository _repo;
  final LeaveRepository _leave;

  Future<void> _load(Emitter<ApprovalsState> emit, String filter,
      {int? decidedNonce, String? lastOutcome}) async {
    final nonce = decidedNonce ?? state.decidedNonce;
    emit(ApprovalsState(
        status: LoadStatus.loading,
        filter: filter,
        inbox: state.inbox,
        decidedNonce: nonce,
        leave: state.leave,
        lastOutcome: lastOutcome ?? state.lastOutcome));
    // The ESS half first: its client rotates an expiring kept sign-in, which
    // the Scheduler half then uses.
    ApprovalInbox? ess;
    Failure? essFailure;
    try {
      ess = await _repo.approvals(status: filter);
    } on Failure catch (f) {
      essFailure = f;
    }
    final leave = await _leave.overviewSafe();
    if (essFailure != null && leave.failure != null) {
      emit(ApprovalsState(
          status: LoadStatus.failure,
          filter: filter,
          failure: essFailure,
          decidedNonce: nonce));
      return;
    }
    // CL/LWP are decided on the Scheduler now; the shared table means the ESS
    // inbox may still list them, so keep only its attendance and WFH rows.
    final essRows = (ess?.requests ?? const <EssRequest>[])
        .where((r) => !(r.isLeave && (r.type == 'cl' || r.type == 'lwp')));
    final overview = leave.data;
    final rows = [...essRows, ...?_leaveRows(overview, filter)];
    // Pending: oldest first, so the longest wait is decided first (#43).
    rows.sort((a, b) {
      final x = a.createdAt ?? DateTime(0);
      final y = b.createdAt ?? DateTime(0);
      return filter == 'pending' ? x.compareTo(y) : y.compareTo(x);
    });
    final leaveCount = rows.where((r) => r.isLeave).length;
    final inbox = ApprovalInbox(
      attendance: rows.length - leaveCount,
      leave: leaveCount,
      total: rows.length,
      requests: rows,
      truncated: ess?.truncated ?? false,
    );
    emit(ApprovalsState(
      status: rows.isEmpty ? LoadStatus.empty : LoadStatus.success,
      filter: filter,
      inbox: inbox,
      decidedNonce: nonce,
      leave: overview,
      lastOutcome: lastOutcome ?? state.lastOutcome,
      // One half missing is shown as a notice; the other half still works.
      partialFailure: essFailure ?? leave.failure,
    ));
  }

  /// The Scheduler's queue for this filter: pending = `approvals`, the rest
  /// from `decided`.
  List<EssRequest>? _leaveRows(LeaveOverview? leave, String filter) {
    if (leave == null) return null;
    return switch (filter) {
      'pending' => leave.approvals,
      'all' => [...leave.approvals, ...leave.decided],
      _ => leave.decided.where((r) => r.status == filter).toList(),
    };
  }

  bool _onScheduler(String id) =>
      state.inbox?.requests.any((r) => r.id == id && r.isSchedulerLeave) ??
      false;

  Future<void> _onDecide(
      ApprovalDecided e, Emitter<ApprovalsState> emit) async {
    emit(state._with(submitting: true));
    try {
      String? outcome;
      if (_onScheduler(e.id)) {
        final decision = await _leave.decide(e.id,
            decision: e.decision,
            note: e.note,
            substituteFacultyId: e.substituteFacultyId,
            classTiming: e.classTiming);
        outcome = decision.outcome;
      } else {
        await _repo.decideRequest(
            family: e.family,
            id: e.id,
            decision: e.decision,
            note: e.note,
            substituteFacultyId: e.substituteFacultyId,
            classTiming: e.classTiming);
        outcome = e.decision == 'approve' ? 'approved' : 'rejected';
      }
      await _load(emit, state.filter,
          decidedNonce: state.decidedNonce + 1, lastOutcome: outcome);
    } on Failure catch (f) {
      emit(state._with(actionFailure: requestFailure(f)));
    }
  }

  Future<void> _onArchive(
      ApprovalArchived e, Emitter<ApprovalsState> emit) async {
    // Archive is an ESS action; the Scheduler has no archive for leave.
    if (_onScheduler(e.id)) return;
    try {
      await _repo.archiveRequest(family: e.family, id: e.id);
      await _load(emit, state.filter);
    } on Failure catch (f) {
      emit(state._with(actionFailure: requestFailure(f)));
    }
  }
}

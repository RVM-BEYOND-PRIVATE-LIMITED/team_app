import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/work_repository.dart';

sealed class InterviewActionEvent {
  const InterviewActionEvent();
}

class InterviewOutcomeSubmitted extends InterviewActionEvent {
  const InterviewOutcomeSubmitted({required this.roundId, required this.outcome, required this.remarks});
  final String roundId;
  final String outcome;
  final String remarks;
}

class InterviewPostponeSubmitted extends InterviewActionEvent {
  const InterviewPostponeSubmitted({required this.roundId, required this.proposedAt, required this.reason});
  final String roundId;
  final DateTime proposedAt;
  final String reason;
}

class InterviewActionCleared extends InterviewActionEvent {
  const InterviewActionCleared();
}

class InterviewActionState extends Equatable {
  const InterviewActionState({this.status = WriteStatus.idle, this.error, this.message});

  final WriteStatus status;
  final String? error;
  final String? message;

  @override
  List<Object?> get props => [status, error, message];
}

/// Records an interview outcome or asks to reschedule
/// (`POST /api/interviews/:roundId/outcome`, `/postpone`).
class InterviewActionBloc extends Bloc<InterviewActionEvent, InterviewActionState> {
  InterviewActionBloc(this._repo) : super(const InterviewActionState()) {
    on<InterviewOutcomeSubmitted>(_outcome);
    on<InterviewPostponeSubmitted>(_postpone);
    on<InterviewActionCleared>((e, emit) => emit(const InterviewActionState()));
  }

  final WorkRepository _repo;

  Future<void> _outcome(InterviewOutcomeSubmitted e, Emitter<InterviewActionState> emit) async {
    emit(const InterviewActionState(status: WriteStatus.submitting));
    try {
      await _repo.recordOutcome(e.roundId, outcome: e.outcome, remarks: e.remarks);
      emit(const InterviewActionState(status: WriteStatus.success, message: 'Outcome recorded.'));
    } on Failure catch (f) {
      emit(InterviewActionState(status: WriteStatus.failure, error: f.message));
    }
  }

  Future<void> _postpone(InterviewPostponeSubmitted e, Emitter<InterviewActionState> emit) async {
    emit(const InterviewActionState(status: WriteStatus.submitting));
    try {
      await _repo.postponeInterview(e.roundId, proposedAt: e.proposedAt, reason: e.reason);
      emit(const InterviewActionState(status: WriteStatus.success, message: 'Reschedule requested.'));
    } on Failure catch (f) {
      emit(InterviewActionState(status: WriteStatus.failure, error: f.message));
    }
  }
}

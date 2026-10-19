import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/hod_repository.dart';

sealed class HodWriteEvent {
  const HodWriteEvent();
}

class RiskLogSubmitted extends HodWriteEvent {
  const RiskLogSubmitted({
    required this.facultyId,
    this.facultyName,
    this.entryType = 'one_on_one',
    this.riskLevel = 'none',
    this.signal,
    this.actionTaken,
    this.escalated = false,
  });
  final String facultyId;
  final String? facultyName;
  final String entryType;
  final String riskLevel;
  final String? signal;
  final String? actionTaken;
  final bool escalated;
}

class FacultyCommentSubmitted extends HodWriteEvent {
  const FacultyCommentSubmitted({required this.facultyId, required this.comment});
  final String facultyId;
  final String comment;
}

class VerdictSubmitted extends HodWriteEvent {
  const VerdictSubmitted({required this.id, required this.verdict, required this.feedback});
  final String id;
  final String verdict;
  final String feedback;
}

class HodWriteCleared extends HodWriteEvent {
  const HodWriteCleared();
}

class HodWriteState extends Equatable {
  const HodWriteState({this.status = WriteStatus.idle, this.error, this.message});

  final WriteStatus status;
  final String? error;
  final String? message;

  HodWriteState copyWith({WriteStatus? status, String? error, String? message, bool clearError = false}) =>
      HodWriteState(status: status ?? this.status, error: clearError ? null : (error ?? this.error), message: message ?? this.message);

  @override
  List<Object?> get props => [status, error, message];
}

/// HOD writes: risk log, a day comment on a team member, and an interview verdict.
class HodWriteBloc extends Bloc<HodWriteEvent, HodWriteState> {
  HodWriteBloc(this._repo) : super(const HodWriteState()) {
    on<RiskLogSubmitted>(_risk);
    on<FacultyCommentSubmitted>(_comment);
    on<VerdictSubmitted>(_verdict);
    on<HodWriteCleared>((e, emit) => emit(const HodWriteState()));
  }

  final HodRepository _repo;

  Future<void> _run(Emitter<HodWriteState> emit, Future<void> Function() action, String message) async {
    emit(const HodWriteState(status: WriteStatus.submitting));
    try {
      await action();
      emit(HodWriteState(status: WriteStatus.success, message: message));
    } on Failure catch (f) {
      emit(HodWriteState(status: WriteStatus.failure, error: f.message));
    }
  }

  Future<void> _risk(RiskLogSubmitted e, Emitter<HodWriteState> emit) => _run(
        emit,
        () => _repo.createRiskLog(
          facultyId: e.facultyId,
          facultyName: e.facultyName,
          entryType: e.entryType,
          riskLevel: e.riskLevel,
          signal: e.signal,
          actionTaken: e.actionTaken,
          escalated: e.escalated,
        ),
        'Risk log saved.',
      );

  Future<void> _comment(FacultyCommentSubmitted e, Emitter<HodWriteState> emit) =>
      _run(emit, () => _repo.createFacultyComment(facultyId: e.facultyId, comment: e.comment), 'Comment saved.');

  Future<void> _verdict(VerdictSubmitted e, Emitter<HodWriteState> emit) =>
      _run(emit, () => _repo.setVerdict(e.id, verdict: e.verdict, feedback: e.feedback), 'Verdict recorded.');
}

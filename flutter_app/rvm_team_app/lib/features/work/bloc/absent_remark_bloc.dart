import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';

sealed class AbsentRemarkEvent {
  const AbsentRemarkEvent();
}

class AbsentRemarkSubmitted extends AbsentRemarkEvent {
  const AbsentRemarkSubmitted({
    required this.batchId,
    required this.date,
    required this.studentId,
    required this.reason,
    this.followUp,
  });

  final String batchId;
  final String date;
  final String studentId;
  final String reason;
  final String? followUp;
}

class AbsentRemarkCleared extends AbsentRemarkEvent {
  const AbsentRemarkCleared();
}

class AbsentRemarkState extends Equatable {
  const AbsentRemarkState(
      {this.status = WriteStatus.idle, this.error, this.forStudentId});

  final WriteStatus status;
  final String? error;
  final String? forStudentId;

  @override
  List<Object?> get props => [status, error, forStudentId];
}

/// Writes an absent student's reason through the ESS
/// (`PATCH /api/ess/me/batches/{id}/attendance/{date}/remarks`, H1).
class AbsentRemarkBloc extends Bloc<AbsentRemarkEvent, AbsentRemarkState> {
  AbsentRemarkBloc(this._repo) : super(const AbsentRemarkState()) {
    on<AbsentRemarkSubmitted>(_submit);
    on<AbsentRemarkCleared>((e, emit) => emit(const AbsentRemarkState()));
  }

  final EssRepository _repo;

  Future<void> _submit(
      AbsentRemarkSubmitted e, Emitter<AbsentRemarkState> emit) async {
    emit(const AbsentRemarkState(status: WriteStatus.submitting));
    try {
      final student = await _repo.updateClassRemark(
        batchId: e.batchId,
        date: e.date,
        studentId: e.studentId,
        absentReason: e.reason,
        followUpComment: e.followUp,
      );
      emit(AbsentRemarkState(
          status: WriteStatus.success, forStudentId: student.id));
    } on Failure catch (f) {
      emit(AbsentRemarkState(status: WriteStatus.failure, error: f.message));
    }
  }
}

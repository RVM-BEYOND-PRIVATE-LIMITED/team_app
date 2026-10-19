import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/work_repository.dart';

sealed class AbsentRemarkEvent {
  const AbsentRemarkEvent();
}

class AbsentRemarkSubmitted extends AbsentRemarkEvent {
  const AbsentRemarkSubmitted({required this.attendanceId, this.reason, this.followUp});
  final String attendanceId;
  final String? reason;
  final String? followUp;
}

class AbsentRemarkCleared extends AbsentRemarkEvent {
  const AbsentRemarkCleared();
}

class AbsentRemarkState extends Equatable {
  const AbsentRemarkState({this.status = WriteStatus.idle, this.error, this.forAttendanceId});

  final WriteStatus status;
  final String? error;
  final String? forAttendanceId;

  @override
  List<Object?> get props => [status, error, forAttendanceId];
}

/// Writes an absent student's reason (`PATCH /api/attendance/remarks`).
class AbsentRemarkBloc extends Bloc<AbsentRemarkEvent, AbsentRemarkState> {
  AbsentRemarkBloc(this._repo) : super(const AbsentRemarkState()) {
    on<AbsentRemarkSubmitted>(_submit);
    on<AbsentRemarkCleared>((e, emit) => emit(const AbsentRemarkState()));
  }

  final WorkRepository _repo;

  Future<void> _submit(AbsentRemarkSubmitted e, Emitter<AbsentRemarkState> emit) async {
    emit(const AbsentRemarkState(status: WriteStatus.submitting));
    try {
      await _repo.updateAbsentRemarks(
        attendanceId: e.attendanceId,
        absentReason: e.reason,
        followUpComment: e.followUp,
      );
      emit(AbsentRemarkState(status: WriteStatus.success, forAttendanceId: e.attendanceId));
    } on Failure catch (f) {
      emit(AbsentRemarkState(status: WriteStatus.failure, error: f.message));
    }
  }
}

import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/work_repository.dart';
import '../../../domain/models.dart';

sealed class MarkAttendanceEvent {
  const MarkAttendanceEvent();
}

class MarkRosterRequested extends MarkAttendanceEvent {
  const MarkRosterRequested();
}

class MarkToggled extends MarkAttendanceEvent {
  const MarkToggled(this.studentId);
  final String studentId;
}

class MarkAllPresent extends MarkAttendanceEvent {
  const MarkAllPresent();
}

class MarkSubmitted extends MarkAttendanceEvent {
  const MarkSubmitted();
}

class MarkAttendanceState extends Equatable {
  const MarkAttendanceState({
    this.status = LoadStatus.initial,
    this.writeStatus = WriteStatus.idle,
    this.students = const [],
    this.present = const {},
    this.error,
  });

  final LoadStatus status;
  final WriteStatus writeStatus;
  final List<AttendanceStudent> students;
  final Map<String, bool> present;
  final String? error;

  int get presentCount => present.values.where((v) => v).length;

  MarkAttendanceState copyWith({
    LoadStatus? status,
    WriteStatus? writeStatus,
    List<AttendanceStudent>? students,
    Map<String, bool>? present,
    String? error,
    bool clearError = false,
  }) =>
      MarkAttendanceState(
        status: status ?? this.status,
        writeStatus: writeStatus ?? this.writeStatus,
        students: students ?? this.students,
        present: present ?? this.present,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [status, writeStatus, students, present, error];
}

/// Loads one batch's marking roster for a date, tracks marks, and upserts them
/// via `POST /api/attendance` ({batchId, date, attendance:[{student_id,is_present}]}).
class MarkAttendanceBloc extends Bloc<MarkAttendanceEvent, MarkAttendanceState> {
  MarkAttendanceBloc(this._repo, {required this.batchId, required this.date}) : super(const MarkAttendanceState()) {
    on<MarkRosterRequested>(_onLoad);
    on<MarkToggled>(_onToggle);
    on<MarkAllPresent>(_onAllPresent);
    on<MarkSubmitted>(_onSubmit);
  }

  final WorkRepository _repo;
  final String batchId;
  final DateTime date;

  String get dateIso =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _onLoad(MarkRosterRequested e, Emitter<MarkAttendanceState> emit) async {
    emit(state.copyWith(status: LoadStatus.loading, clearError: true));
    try {
      final students = await _repo.dailyAttendance(batchId, dateIso);
      emit(state.copyWith(
        status: students.isEmpty ? LoadStatus.empty : LoadStatus.success,
        students: students,
        present: {for (final s in students) s.studentId: s.isPresent},
      ));
    } on Failure catch (f) {
      emit(state.copyWith(status: LoadStatus.failure, error: f.message));
    }
  }

  void _onToggle(MarkToggled e, Emitter<MarkAttendanceState> emit) {
    final next = Map<String, bool>.from(state.present);
    next[e.studentId] = !(next[e.studentId] ?? false);
    emit(state.copyWith(present: next));
  }

  void _onAllPresent(MarkAllPresent e, Emitter<MarkAttendanceState> emit) {
    emit(state.copyWith(present: {for (final s in state.students) s.studentId: true}));
  }

  Future<void> _onSubmit(MarkSubmitted e, Emitter<MarkAttendanceState> emit) async {
    emit(state.copyWith(writeStatus: WriteStatus.submitting, clearError: true));
    try {
      await _repo.markAttendance(batchId: batchId, date: dateIso, present: state.present);
      emit(state.copyWith(writeStatus: WriteStatus.success));
    } on Failure catch (f) {
      emit(state.copyWith(writeStatus: WriteStatus.failure, error: f.message));
    }
  }
}

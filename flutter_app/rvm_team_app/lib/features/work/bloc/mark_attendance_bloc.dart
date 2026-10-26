import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

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
    this.alreadyMarked = false,
    this.canEdit = true,
    this.error,
  });

  final LoadStatus status;
  final WriteStatus writeStatus;
  final List<ClassRosterStudent> students;
  final Map<String, bool> present;
  final bool alreadyMarked;
  final bool canEdit;
  final String? error;

  int get presentCount => present.values.where((v) => v).length;

  MarkAttendanceState copyWith({
    LoadStatus? status,
    WriteStatus? writeStatus,
    List<ClassRosterStudent>? students,
    Map<String, bool>? present,
    bool? alreadyMarked,
    bool? canEdit,
    String? error,
    bool clearError = false,
  }) =>
      MarkAttendanceState(
        status: status ?? this.status,
        writeStatus: writeStatus ?? this.writeStatus,
        students: students ?? this.students,
        present: present ?? this.present,
        alreadyMarked: alreadyMarked ?? this.alreadyMarked,
        canEdit: canEdit ?? this.canEdit,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props =>
      [status, writeStatus, students, present, alreadyMarked, canEdit, error];
}

/// Loads one batch's ESS marking roster, tracks marks, and saves the day through
/// `POST /api/ess/me/batches/{id}/attendance` (H1, decision 8).
class MarkAttendanceBloc
    extends Bloc<MarkAttendanceEvent, MarkAttendanceState> {
  MarkAttendanceBloc(this._repo, {required this.batchId, required this.date})
      : super(const MarkAttendanceState()) {
    on<MarkRosterRequested>(_onLoad);
    on<MarkToggled>(_onToggle);
    on<MarkAllPresent>(_onAllPresent);
    on<MarkSubmitted>(_onSubmit);
  }

  final EssRepository _repo;
  final String batchId;
  final DateTime date;

  String get dateIso =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _onLoad(
      MarkRosterRequested e, Emitter<MarkAttendanceState> emit) async {
    emit(state.copyWith(status: LoadStatus.loading, clearError: true));
    try {
      final roster = await _repo.classRoster(batchId: batchId, date: dateIso);
      emit(_fromRoster(roster));
    } on Failure catch (f) {
      emit(state.copyWith(status: LoadStatus.failure, error: f.message));
    }
  }

  MarkAttendanceState _fromRoster(ClassRoster roster) => state.copyWith(
        status: roster.students.isEmpty ? LoadStatus.empty : LoadStatus.success,
        students: roster.students,
        present: {
          for (final s in roster.students) s.id: s.isPresent,
        },
        alreadyMarked: roster.alreadyMarked,
        canEdit: roster.canEdit,
        clearError: true,
      );

  void _onToggle(MarkToggled e, Emitter<MarkAttendanceState> emit) {
    if (!state.canEdit) return;
    final next = Map<String, bool>.from(state.present);
    next[e.studentId] = !(next[e.studentId] ?? false);
    emit(state.copyWith(present: next));
  }

  void _onAllPresent(MarkAllPresent e, Emitter<MarkAttendanceState> emit) {
    if (!state.canEdit) return;
    emit(state.copyWith(present: {for (final s in state.students) s.id: true}));
  }

  Future<void> _onSubmit(
      MarkSubmitted e, Emitter<MarkAttendanceState> emit) async {
    if (!state.canEdit) return;
    emit(state.copyWith(writeStatus: WriteStatus.submitting, clearError: true));
    try {
      await _repo.saveClassAttendance(
        batchId: batchId,
        date: dateIso,
        present: state.present,
        absentReasons: {
          for (final s in state.students) s.id: s.absentReason,
        },
        followUps: {
          for (final s in state.students) s.id: s.followUpComment,
        },
      );
    } on Failure catch (f) {
      emit(state.copyWith(writeStatus: WriteStatus.failure, error: f.message));
      return;
    }

    emit(state.copyWith(writeStatus: WriteStatus.success));
    // The server decides the lock after the save: a teaching role can no longer
    // edit the day, an admin still can. Read that state back.
    try {
      final roster = await _repo.classRoster(batchId: batchId, date: dateIso);
      emit(_fromRoster(roster).copyWith(writeStatus: WriteStatus.success));
    } on Failure {
      // The save succeeded; a failed re-read must not turn it into a failure.
    }
  }
}

import 'dart:async';

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

/// Re-reads the roster in place, on pull-to-refresh or when the app comes back
/// to the foreground (#57 item 4). Unlike [MarkRosterRequested] it never shows
/// the full-screen loader, and it keeps the marks changed on this phone that
/// are not saved yet (see [MarkAttendanceBloc]).
class MarkRosterRefreshed extends MarkAttendanceEvent {
  const MarkRosterRefreshed({this.done});

  /// Completed once the re-read is over: with null when it worked or was not
  /// needed, or with the reason it failed. A pull-to-refresh spinner waits on
  /// it and shows that reason.
  final Completer<String?>? done;
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
///
/// [MarkRosterRefreshed] re-reads the same `GET /me/batches/{id}/roster` in
/// place. While the server still lets this person edit the day (`can_edit`),
/// a student whose mark was changed on this phone keeps it and every other
/// student takes the server's mark. For a teaching role that keeps the toggles
/// while the day is unsaved: once anyone saves it, the server locks it for them
/// and its marks are taken, as after a save here.
class MarkAttendanceBloc
    extends Bloc<MarkAttendanceEvent, MarkAttendanceState> {
  MarkAttendanceBloc(this._repo, {required this.batchId, required this.date})
      : super(const MarkAttendanceState()) {
    on<MarkRosterRequested>(_onLoad);
    on<MarkRosterRefreshed>(_onRefresh);
    on<MarkToggled>(_onToggle);
    on<MarkAllPresent>(_onAllPresent);
    on<MarkSubmitted>(_onSubmit);
  }

  final EssRepository _repo;
  final String batchId;
  final DateTime date;

  /// Bumped by every full load and every save. A refresh whose reply lands
  /// after either one started drops that reply, so it never overwrites newer
  /// marks or the lock a save reads back.
  int _generation = 0;
  bool _refreshing = false;

  String get dateIso =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _onLoad(
      MarkRosterRequested e, Emitter<MarkAttendanceState> emit) async {
    _generation++;
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

  Future<void> _onRefresh(
      MarkRosterRefreshed e, Emitter<MarkAttendanceState> emit) async {
    // Nothing to refresh yet, or a newer read is on its way: the first load,
    // another refresh, or a save (which reads the roster back itself).
    if (_refreshing ||
        state.status == LoadStatus.initial ||
        state.status == LoadStatus.loading ||
        state.writeStatus == WriteStatus.submitting) {
      e.done?.complete();
      return;
    }
    _refreshing = true;
    final generation = _generation;
    String? error;
    try {
      final roster = await _repo.classRoster(batchId: batchId, date: dateIso);
      if (generation == _generation) emit(_refreshed(roster));
    } on Failure catch (f) {
      // The roster and the marks on screen stay as they are.
      error = f.message;
    } finally {
      _refreshing = false;
      e.done?.complete(error);
    }
  }

  /// [roster] with the marks changed on this phone and not saved yet, while
  /// the server lets this person edit the day. Students who left the roster
  /// drop out, so a save never sends them; one who joined starts from the
  /// server's mark.
  MarkAttendanceState _refreshed(ClassRoster roster) {
    final fresh = _fromRoster(roster);
    if (!roster.canEdit) return fresh;
    final server = {for (final s in state.students) s.id: s.isPresent};
    bool changedHere(String id) =>
        server.containsKey(id) &&
        state.present.containsKey(id) &&
        server[id] != state.present[id];
    return fresh.copyWith(present: {
      for (final s in roster.students)
        s.id: changedHere(s.id) ? state.present[s.id]! : s.isPresent,
    });
  }

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
    _generation++;
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

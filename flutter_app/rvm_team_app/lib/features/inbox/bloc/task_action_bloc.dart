import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/priority_tasks_repository.dart';
import '../../../domain/models.dart';

sealed class TaskActionEvent {
  const TaskActionEvent();
}

class TaskAcknowledged extends TaskActionEvent {
  const TaskAcknowledged(this.id);
  final String id;
}

class TaskStatusChanged extends TaskActionEvent {
  const TaskStatusChanged({required this.id, required this.status});
  final String id;
  final String status;
}

class TaskProgressSaved extends TaskActionEvent {
  const TaskProgressSaved({required this.id, required this.note});
  final String id;
  final String note;
}

class TaskActionCleared extends TaskActionEvent {
  const TaskActionCleared();
}

class TaskActionState extends Equatable {
  const TaskActionState({this.status = WriteStatus.idle, this.error, this.task});

  final WriteStatus status;
  final String? error;
  final PriorityTask? task;

  TaskActionState copyWith({WriteStatus? status, String? error, PriorityTask? task, bool clearError = false}) =>
      TaskActionState(
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        task: task ?? this.task,
      );

  @override
  List<Object?> get props => [status, error, task];
}

/// Writes to one priority task: acknowledge a read, move its status, or save a
/// progress note. (Cancelling is set by whoever set the task, not the inbox.)
class TaskActionBloc extends Bloc<TaskActionEvent, TaskActionState> {
  TaskActionBloc(this._repo) : super(const TaskActionState()) {
    on<TaskAcknowledged>(_ack);
    on<TaskStatusChanged>(_status);
    on<TaskProgressSaved>(_progress);
    on<TaskActionCleared>((e, emit) => emit(const TaskActionState()));
  }

  final PriorityTasksRepository _repo;

  Future<void> _ack(TaskAcknowledged e, Emitter<TaskActionState> emit) async {
    emit(state.copyWith(status: WriteStatus.submitting, clearError: true));
    try {
      await _repo.acknowledge(e.id);
      emit(state.copyWith(status: WriteStatus.success));
    } on Failure catch (f) {
      emit(state.copyWith(status: WriteStatus.failure, error: f.message));
    }
  }

  Future<void> _status(TaskStatusChanged e, Emitter<TaskActionState> emit) async {
    emit(state.copyWith(status: WriteStatus.submitting, clearError: true));
    try {
      final task = await _repo.update(e.id, status: e.status);
      emit(state.copyWith(status: WriteStatus.success, task: task));
    } on Failure catch (f) {
      emit(state.copyWith(status: WriteStatus.failure, error: f.message));
    }
  }

  Future<void> _progress(TaskProgressSaved e, Emitter<TaskActionState> emit) async {
    emit(state.copyWith(status: WriteStatus.submitting, clearError: true));
    try {
      final task = await _repo.update(e.id, progressNote: e.note);
      emit(state.copyWith(status: WriteStatus.success, task: task));
    } on Failure catch (f) {
      emit(state.copyWith(status: WriteStatus.failure, error: f.message));
    }
  }
}

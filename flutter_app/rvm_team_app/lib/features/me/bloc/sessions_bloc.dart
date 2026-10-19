import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

sealed class SessionsEvent {
  const SessionsEvent();
}

class SessionsLoadRequested extends SessionsEvent {
  const SessionsLoadRequested();
}

class SessionsRefreshed extends SessionsEvent {
  const SessionsRefreshed();
}

/// End one kept sign-in ("sign out everywhere" minus the current device), A3.
class SessionEndRequested extends SessionsEvent {
  const SessionEndRequested(this.id);
  final String id;
}

class SessionsState extends Equatable {
  const SessionsState({
    this.status = LoadStatus.initial,
    this.sessions = const [],
    this.failure,
    this.endingId,
    this.endFailure,
  });

  final LoadStatus status;
  final List<TeamSession> sessions;
  final Failure? failure;
  final String? endingId;
  final Failure? endFailure;

  @override
  List<Object?> get props => [status, sessions, failure, endingId, endFailure];
}

class SessionsBloc extends Bloc<SessionsEvent, SessionsState> {
  SessionsBloc(this._repo) : super(const SessionsState()) {
    on<SessionsLoadRequested>(_onLoad);
    on<SessionsRefreshed>(_onLoad);
    on<SessionEndRequested>(_onEnd);
  }

  final EssRepository _repo;

  Future<void> _onLoad(SessionsEvent e, Emitter<SessionsState> emit) async {
    emit(SessionsState(status: LoadStatus.loading, sessions: state.sessions));
    try {
      final list = await _repo.sessions();
      emit(SessionsState(
        status: list.isEmpty ? LoadStatus.empty : LoadStatus.success,
        sessions: list,
      ));
    } on Failure catch (f) {
      emit(SessionsState(status: LoadStatus.failure, failure: f));
    }
  }

  Future<void> _onEnd(SessionEndRequested e, Emitter<SessionsState> emit) async {
    emit(SessionsState(status: state.status, sessions: state.sessions, endingId: e.id));
    try {
      await _repo.endSession(e.id);
      final list = await _repo.sessions();
      emit(SessionsState(
        status: list.isEmpty ? LoadStatus.empty : LoadStatus.success,
        sessions: list,
      ));
    } on Failure catch (f) {
      emit(SessionsState(status: state.status, sessions: state.sessions, endFailure: f));
    }
  }
}

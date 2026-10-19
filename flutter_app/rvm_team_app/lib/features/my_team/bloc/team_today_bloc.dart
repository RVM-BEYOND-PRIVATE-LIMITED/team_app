import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

/// E6/H4: Team today, with the all · not_in · late · on_leave filter chips.
sealed class TeamTodayEvent {
  const TeamTodayEvent();
}

class TeamTodayLoadRequested extends TeamTodayEvent {
  const TeamTodayLoadRequested();
}

class TeamTodayFiltered extends TeamTodayEvent {
  const TeamTodayFiltered(this.filter);
  final String filter;
}

class TeamTodayState extends Equatable {
  const TeamTodayState({this.status = LoadStatus.initial, this.filter = 'all', this.data, this.failure});
  final LoadStatus status;
  final String filter;
  final TeamTodayView? data;
  final Failure? failure;
  @override
  List<Object?> get props => [status, filter, data, failure];
}

class TeamTodayBloc extends Bloc<TeamTodayEvent, TeamTodayState> {
  TeamTodayBloc(this._repo) : super(const TeamTodayState()) {
    on<TeamTodayLoadRequested>((_, emit) => _run(emit, state.filter));
    on<TeamTodayFiltered>((e, emit) => _run(emit, e.filter));
  }

  final EssRepository _repo;

  Future<void> _run(Emitter<TeamTodayState> emit, String filter) async {
    emit(TeamTodayState(status: LoadStatus.loading, filter: filter, data: state.data));
    try {
      final data = await _repo.teamToday(filter: filter);
      emit(TeamTodayState(status: LoadStatus.success, filter: filter, data: data));
    } on Failure catch (f) {
      emit(TeamTodayState(status: LoadStatus.failure, filter: filter, failure: f));
    }
  }
}

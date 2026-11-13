import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/team_modules.dart';

// ── events ──────────────────────────────────────────────────────────────
sealed class TeamModulesEvent {
  const TeamModulesEvent();
}

/// Ask which modules are open: the shell has started, after a launch or a
/// sign-in.
class TeamModulesLoadRequested extends TeamModulesEvent {
  const TeamModulesLoadRequested();
}

/// Ask again: the app has come back to the foreground. Does nothing before
/// the first ask of this sign-in, or after sign-out.
class TeamModulesRefreshRequested extends TeamModulesEvent {
  const TeamModulesRefreshRequested();
}

/// Signed out (or the session ended): nothing is open, and an answer still on
/// its way for the old session is dropped.
class TeamModulesCleared extends TeamModulesEvent {
  const TeamModulesCleared();
}

// ── state ───────────────────────────────────────────────────────────────
enum TeamModulesStatus {
  /// Not asked in this session. Nothing is open.
  unknown,

  /// A request is on its way. What was open stays open until it answers.
  loading,

  /// Answered. A failed request answers [TeamModules.none].
  ready,
}

class TeamModulesState extends Equatable {
  const TeamModulesState({
    this.status = TeamModulesStatus.unknown,
    this.modules = TeamModules.none,
  });

  final TeamModulesStatus status;
  final TeamModules modules;

  @override
  List<Object?> get props => [status, modules];
}

// ── bloc ────────────────────────────────────────────────────────────────

/// The staff modules open to the signed-in person (team_app #50, items 5 and
/// 7b). The router's module guard reads [TeamModulesState.modules]: before
/// the first answer, after any failure and after sign-out nothing is open,
/// which is how the app behaved before modules existed.
///
/// [load] never throws (`TeamModulesRepository.modules`); a throw here is
/// still read as nothing open. One request at a time: an ask while one is on
/// its way is dropped, so a foreground burst cannot become a request storm.
class TeamModulesBloc extends Bloc<TeamModulesEvent, TeamModulesState> {
  TeamModulesBloc(this._load) : super(const TeamModulesState()) {
    on<TeamModulesLoadRequested>((_, emit) => _ask(emit));
    on<TeamModulesRefreshRequested>((_, emit) async {
      if (state.status == TeamModulesStatus.unknown) return;
      await _ask(emit);
    });
    on<TeamModulesCleared>((_, emit) {
      _session++;
      _asking = false;
      emit(const TeamModulesState());
    });
  }

  final Future<TeamModules> Function() _load;

  /// Bumped on every sign-out, so an answer for an earlier session is dropped.
  int _session = 0;
  bool _asking = false;

  Future<void> _ask(Emitter<TeamModulesState> emit) async {
    if (_asking) return;
    _asking = true;
    final session = _session;
    emit(TeamModulesState(
        status: TeamModulesStatus.loading, modules: state.modules));
    TeamModules modules;
    try {
      modules = await _load();
    } catch (_) {
      modules = TeamModules.none;
    }
    if (session != _session) return;
    _asking = false;
    emit(TeamModulesState(status: TeamModulesStatus.ready, modules: modules));
  }
}

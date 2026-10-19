import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Events for a data-load flow.
sealed class LoadEvent {
  const LoadEvent();
}

/// Initial load (only fetches if not already loaded).
class LoadRequested extends LoadEvent {
  const LoadRequested();
}

/// Force refetch (pull-to-refresh / retry).
class LoadRefreshed extends LoadEvent {
  const LoadRefreshed();
}

enum LoadStatus { initial, loading, success, empty, failure }

/// One state shape for every "load a value/list with loading·success·empty·
/// error" flow. [failure] carries the real cause for centered messages.
class LoadState<T> extends Equatable {
  const LoadState({this.status = LoadStatus.initial, this.data, this.failure});

  final LoadStatus status;
  final T? data;
  final Failure? failure;

  bool get isLoading => status == LoadStatus.loading;

  LoadState<T> copyWith({LoadStatus? status, T? data, Failure? failure}) =>
      LoadState<T>(status: status ?? this.status, data: data ?? this.data, failure: failure ?? this.failure);

  @override
  List<Object?> get props => [status, data, failure];
}

/// Generic loader Bloc (event → state). Reused for announcements, recommended
/// jobs, applications, profile, … Each instance is given its fetch function and
/// an optional emptiness test, so all four states are exercised by one test.
class LoadBloc<T> extends Bloc<LoadEvent, LoadState<T>> {
  LoadBloc(this._fetch, {bool Function(T data)? isEmpty})
      : _isEmpty = isEmpty,
        super(LoadState<T>()) {
    on<LoadRequested>((e, emit) async {
      if (state.status == LoadStatus.success || state.status == LoadStatus.empty) return;
      await _run(emit);
    });
    on<LoadRefreshed>((e, emit) => _run(emit));
  }

  final Future<T> Function() _fetch;
  final bool Function(T data)? _isEmpty;

  Future<void> _run(Emitter<LoadState<T>> emit) async {
    emit(LoadState<T>(status: LoadStatus.loading, data: state.data));
    try {
      // Hard backstop so a load can NEVER hang the skeleton forever — even if
      // something bypasses the network-layer timeout (an interceptor async gap,
      // a stalled DNS/socket, a platform-channel hiccup). Resolves to a real
      // error + retry instead. Sits just above the 30s dio timeout.
      final data = await _fetch().timeout(const Duration(seconds: 35));
      final empty = _isEmpty?.call(data) ?? false;
      emit(LoadState<T>(status: empty ? LoadStatus.empty : LoadStatus.success, data: data));
    } on Failure catch (f) {
      emit(LoadState<T>(status: LoadStatus.failure, failure: f));
    } catch (_) {
      // Never leave the UI stuck on the loading skeleton: any non-Failure error
      // (e.g. a connectivity PlatformException, a parse edge case) still resolves
      // to a real error state with a retry, instead of hanging forever.
      emit(LoadState<T>(status: LoadStatus.failure, failure: const UnknownFailure()));
    }
  }
}

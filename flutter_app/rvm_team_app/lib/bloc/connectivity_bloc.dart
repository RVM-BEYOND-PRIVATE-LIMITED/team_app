import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class ConnectivityEvent {
  const ConnectivityEvent();
}

class _StatusChanged extends ConnectivityEvent {
  const _StatusChanged(this.online);
  final bool online;
}

class ConnectivityState extends Equatable {
  const ConnectivityState({required this.online});
  final bool online;
  @override
  List<Object?> get props => [online];
}

/// Watches [ConnectivityService] (interface + reachability) → online/offline.
/// Drives the offline banner + "No internet connection" state.
class ConnectivityBloc extends Bloc<ConnectivityEvent, ConnectivityState> {
  ConnectivityBloc(this._service) : super(const ConnectivityState(online: true)) {
    on<_StatusChanged>((e, emit) => emit(ConnectivityState(online: e.online)));
    _sub = _service.onStatusChanged().listen((online) => add(_StatusChanged(online)));
  }

  final ConnectivityService _service;
  late final StreamSubscription<bool> _sub;

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}

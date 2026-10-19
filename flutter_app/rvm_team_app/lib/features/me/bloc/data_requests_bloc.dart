import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

sealed class DataRequestsEvent {
  const DataRequestsEvent();
}

class DataRequestsLoadRequested extends DataRequestsEvent {
  const DataRequestsLoadRequested();
}

class DataRequestsRefreshed extends DataRequestsEvent {
  const DataRequestsRefreshed();
}

/// Raise a request to correct or delete one's own data (A8). `details` must be
/// 5–2,000 characters; the server enforces it.
class DataRequestCreateRequested extends DataRequestsEvent {
  const DataRequestCreateRequested({required this.kind, required this.details});
  final String kind; // correct | delete
  final String details;
}

class DataRequestsState extends Equatable {
  const DataRequestsState({
    this.status = LoadStatus.initial,
    this.requests = const [],
    this.failure,
    this.submitting = false,
    this.submitFailure,
    this.createdNonce = 0,
  });

  final LoadStatus status;
  final List<EssDataRequest> requests;
  final Failure? failure;
  final bool submitting;
  final Failure? submitFailure;
  final int createdNonce;

  @override
  List<Object?> get props => [status, requests, failure, submitting, submitFailure, createdNonce];
}

class DataRequestsBloc extends Bloc<DataRequestsEvent, DataRequestsState> {
  DataRequestsBloc(this._repo) : super(const DataRequestsState()) {
    on<DataRequestsLoadRequested>(_onLoad);
    on<DataRequestsRefreshed>(_onLoad);
    on<DataRequestCreateRequested>(_onCreate);
  }

  final EssRepository _repo;

  Future<void> _onLoad(DataRequestsEvent e, Emitter<DataRequestsState> emit) async {
    emit(DataRequestsState(status: LoadStatus.loading, requests: state.requests, createdNonce: state.createdNonce));
    try {
      final list = await _repo.myDataRequests();
      emit(DataRequestsState(
        status: list.isEmpty ? LoadStatus.empty : LoadStatus.success,
        requests: list,
        createdNonce: state.createdNonce,
      ));
    } on Failure catch (f) {
      emit(DataRequestsState(status: LoadStatus.failure, failure: f, createdNonce: state.createdNonce));
    }
  }

  Future<void> _onCreate(DataRequestCreateRequested e, Emitter<DataRequestsState> emit) async {
    emit(DataRequestsState(
      status: state.status,
      requests: state.requests,
      submitting: true,
      createdNonce: state.createdNonce,
    ));
    try {
      await _repo.createDataRequest(kind: e.kind, details: e.details);
      final list = await _repo.myDataRequests();
      emit(DataRequestsState(
        status: list.isEmpty ? LoadStatus.empty : LoadStatus.success,
        requests: list,
        createdNonce: state.createdNonce + 1,
      ));
    } on Failure catch (f) {
      emit(DataRequestsState(
        status: state.status,
        requests: state.requests,
        submitFailure: f,
        createdNonce: state.createdNonce,
      ));
    }
  }
}

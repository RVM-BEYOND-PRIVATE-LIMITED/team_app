import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

/// The three HR review queues the 1B backend exposes.
enum HrQueue { dataRequests, reports, devices }

sealed class HrToolsEvent {
  const HrToolsEvent();
}

class HrQueueSelected extends HrToolsEvent {
  const HrQueueSelected(this.queue);
  final HrQueue queue;
}

class HrToolsLoadRequested extends HrToolsEvent {
  const HrToolsLoadRequested();
}

class HrToolsRefreshed extends HrToolsEvent {
  const HrToolsRefreshed();
}

class HrResolveDataRequestRequested extends HrToolsEvent {
  const HrResolveDataRequestRequested({required this.id, required this.status, this.note});
  final String id;
  final String status; // done | rejected
  final String? note;
}

class HrResetDevicesRequested extends HrToolsEvent {
  const HrResetDevicesRequested({required this.employeeIds, required this.reason});
  final List<String> employeeIds;
  final String reason;
}

class HrToolsState extends Equatable {
  const HrToolsState({
    this.queue = HrQueue.dataRequests,
    this.status = LoadStatus.initial,
    this.dataRequests = const [],
    this.reports = const [],
    this.devices = const [],
    this.truncated = false,
    this.failure,
    this.submitting = false,
    this.actionFailure,
    this.actionNonce = 0,
  });

  final HrQueue queue;
  final LoadStatus status;
  final List<EssDataRequest> dataRequests;
  final List<MockLocationReport> reports;
  final List<RegisteredPhone> devices;
  final bool truncated;
  final Failure? failure;
  final bool submitting;
  final Failure? actionFailure;
  final int actionNonce;

  @override
  List<Object?> get props =>
      [queue, status, dataRequests, reports, devices, truncated, failure, submitting, actionFailure, actionNonce];
}

class HrToolsBloc extends Bloc<HrToolsEvent, HrToolsState> {
  HrToolsBloc(this._repo) : super(const HrToolsState()) {
    on<HrQueueSelected>(_onSelect);
    on<HrToolsLoadRequested>(_onLoad);
    on<HrToolsRefreshed>(_onLoad);
    on<HrResolveDataRequestRequested>(_onResolve);
    on<HrResetDevicesRequested>(_onReset);
  }

  final EssRepository _repo;

  Future<void> _onSelect(HrQueueSelected e, Emitter<HrToolsState> emit) async {
    emit(_copy(queue: e.queue, status: LoadStatus.loading));
    await _load(e.queue, emit);
  }

  Future<void> _onLoad(HrToolsEvent e, Emitter<HrToolsState> emit) async {
    emit(_copy(status: LoadStatus.loading));
    await _load(state.queue, emit);
  }

  Future<void> _load(HrQueue queue, Emitter<HrToolsState> emit) async {
    try {
      switch (queue) {
        case HrQueue.dataRequests:
          final r = await _repo.hrDataRequests();
          emit(_copy(
            status: r.requests.isEmpty ? LoadStatus.empty : LoadStatus.success,
            dataRequests: r.requests,
            truncated: r.truncated,
          ));
        case HrQueue.reports:
          final r = await _repo.mockLocationReports();
          emit(_copy(
            status: r.reports.isEmpty ? LoadStatus.empty : LoadStatus.success,
            reports: r.reports,
            truncated: r.truncated,
          ));
        case HrQueue.devices:
          final r = await _repo.devices();
          emit(_copy(
            status: r.devices.isEmpty ? LoadStatus.empty : LoadStatus.success,
            devices: r.devices,
            truncated: r.truncated,
          ));
      }
    } on Failure catch (f) {
      emit(_copy(status: LoadStatus.failure, failure: f));
    }
  }

  Future<void> _onResolve(HrResolveDataRequestRequested e, Emitter<HrToolsState> emit) async {
    emit(_copy(submitting: true));
    try {
      await _repo.resolveDataRequest(e.id, status: e.status, note: e.note);
      final r = await _repo.hrDataRequests();
      emit(_copy(
        status: r.requests.isEmpty ? LoadStatus.empty : LoadStatus.success,
        dataRequests: r.requests,
        truncated: r.truncated,
        actionNonce: state.actionNonce + 1,
      ));
    } on Failure catch (f) {
      emit(_copy(actionFailure: f));
    }
  }

  Future<void> _onReset(HrResetDevicesRequested e, Emitter<HrToolsState> emit) async {
    emit(_copy(submitting: true));
    try {
      await _repo.resetDevices({'employee_ids': e.employeeIds, 'reason': e.reason});
      final r = await _repo.devices();
      emit(_copy(
        status: r.devices.isEmpty ? LoadStatus.empty : LoadStatus.success,
        devices: r.devices,
        truncated: r.truncated,
        actionNonce: state.actionNonce + 1,
      ));
    } on Failure catch (f) {
      emit(_copy(actionFailure: f));
    }
  }

  /// Fresh state with the given overrides; `failure`/`actionFailure` cleared
  /// unless explicitly passed.
  HrToolsState _copy({
    HrQueue? queue,
    LoadStatus? status,
    List<EssDataRequest>? dataRequests,
    List<MockLocationReport>? reports,
    List<RegisteredPhone>? devices,
    bool? truncated,
    Failure? failure,
    bool? submitting,
    Failure? actionFailure,
    int? actionNonce,
  }) =>
      HrToolsState(
        queue: queue ?? state.queue,
        status: status ?? state.status,
        dataRequests: dataRequests ?? state.dataRequests,
        reports: reports ?? state.reports,
        devices: devices ?? state.devices,
        truncated: truncated ?? state.truncated,
        failure: failure,
        submitting: submitting ?? false,
        actionFailure: actionFailure,
        actionNonce: actionNonce ?? state.actionNonce,
      );
}

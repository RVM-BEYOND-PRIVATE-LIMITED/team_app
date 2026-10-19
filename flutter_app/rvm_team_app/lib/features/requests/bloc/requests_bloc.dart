import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

/// C1–C5: my attendance and leave requests, and the month's balances.
sealed class RequestsEvent {
  const RequestsEvent();
}

class RequestsLoadRequested extends RequestsEvent {
  const RequestsLoadRequested();
}

class RequestsRefreshed extends RequestsEvent {
  const RequestsRefreshed();
}

/// Raise one request. `family` is attendance | leave; `type` is the family's own type.
class RequestCreateRequested extends RequestsEvent {
  const RequestCreateRequested({
    required this.family,
    required this.type,
    required this.day,
    required this.reason,
    this.place,
    this.fixIn,
    this.fixOut,
    this.minutes,
  });
  final String family;
  final String type;
  final String day;
  final String reason;
  final String? place;
  final String? fixIn;
  final String? fixOut;
  final int? minutes;
}

class RequestWithdrawRequested extends RequestsEvent {
  const RequestWithdrawRequested({required this.family, required this.id});
  final String family;
  final String id;
}

class RequestsState extends Equatable {
  const RequestsState({
    this.status = LoadStatus.initial,
    this.requests = const [],
    this.balances,
    this.failure,
    this.submitting = false,
    this.submitFailure,
    this.createdNonce = 0,
  });

  final LoadStatus status;
  final List<EssRequest> requests;
  final LeaveBalances? balances;
  final Failure? failure;
  final bool submitting;
  final Failure? submitFailure;
  final int createdNonce;

  @override
  List<Object?> get props => [status, requests, balances, failure, submitting, submitFailure, createdNonce];
}

class RequestsBloc extends Bloc<RequestsEvent, RequestsState> {
  RequestsBloc(this._repo) : super(const RequestsState()) {
    on<RequestsLoadRequested>((_, emit) => _load(emit));
    on<RequestsRefreshed>((_, emit) => _load(emit));
    on<RequestCreateRequested>(_onCreate);
    on<RequestWithdrawRequested>(_onWithdraw);
  }

  final EssRepository _repo;

  Future<void> _load(Emitter<RequestsState> emit) async {
    emit(RequestsState(
      status: LoadStatus.loading,
      requests: state.requests,
      balances: state.balances,
      createdNonce: state.createdNonce,
    ));
    try {
      final balances = await _repo.leaveBalances();
      final attendance = await _repo.myAttendanceRequests();
      final leave = await _repo.myLeaveRequests();
      final all = [...attendance, ...leave]
        ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      emit(RequestsState(
        status: all.isEmpty ? LoadStatus.empty : LoadStatus.success,
        requests: all,
        balances: balances,
        createdNonce: state.createdNonce,
      ));
    } on Failure catch (f) {
      emit(RequestsState(status: LoadStatus.failure, failure: f, createdNonce: state.createdNonce));
    }
  }

  Future<void> _onCreate(RequestCreateRequested e, Emitter<RequestsState> emit) async {
    emit(RequestsState(status: state.status, requests: state.requests, balances: state.balances, submitting: true, createdNonce: state.createdNonce));
    try {
      if (e.family == 'leave') {
        await _repo.createLeaveRequest(type: e.type, day: e.day, reason: e.reason);
      } else {
        await _repo.createAttendanceRequest(
          type: e.type, day: e.day, reason: e.reason, place: e.place, fixIn: e.fixIn, fixOut: e.fixOut, minutes: e.minutes);
      }
      final created = state.createdNonce + 1;
      emit(RequestsState(status: state.status, requests: state.requests, balances: state.balances, createdNonce: created));
      await _load(emit);
    } on Failure catch (f) {
      emit(RequestsState(status: state.status, requests: state.requests, balances: state.balances, submitFailure: f, createdNonce: state.createdNonce));
    }
  }

  Future<void> _onWithdraw(RequestWithdrawRequested e, Emitter<RequestsState> emit) async {
    try {
      if (e.family == 'leave') {
        await _repo.withdrawLeaveRequest(e.id);
      } else {
        await _repo.withdrawAttendanceRequest(e.id);
      }
      await _load(emit);
    } on Failure catch (f) {
      emit(RequestsState(status: state.status, requests: state.requests, balances: state.balances, submitFailure: f, createdNonce: state.createdNonce));
    }
  }
}

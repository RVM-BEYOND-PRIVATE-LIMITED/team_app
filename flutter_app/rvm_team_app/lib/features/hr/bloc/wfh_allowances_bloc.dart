import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

/// HR's per-employee WFH allowances (`GET/PUT /hr/wfh-allowances`, KP 22 Oct).
/// HR, the CEO and super admins only; the server is the permission.
sealed class WfhAllowancesEvent {
  const WfhAllowancesEvent();
}

class WfhAllowancesLoadRequested extends WfhAllowancesEvent {
  const WfhAllowancesLoadRequested([this.query = '']);
  final String query;
}

class WfhAllowancesSearchChanged extends WfhAllowancesEvent {
  const WfhAllowancesSearchChanged(this.query);
  final String query;
}

class WfhAllowancesSaved extends WfhAllowancesEvent {
  const WfhAllowancesSaved({
    required this.employeeId,
    required this.enabled,
    required this.monthlyLimitDays,
    this.note,
  });
  final String employeeId;
  final bool enabled;
  final int monthlyLimitDays;
  final String? note;
}

class WfhAllowancesState extends Equatable {
  const WfhAllowancesState({
    this.status = LoadStatus.initial,
    this.query = '',
    this.page,
    this.failure,
    this.actionFailure,
    this.submitting = false,
    this.savedNonce = 0,
  });

  final LoadStatus status;
  final String query;
  final HrWfhAllowancePage? page;
  final Failure? failure;
  final Failure? actionFailure;
  final bool submitting;
  final int savedNonce;

  @override
  List<Object?> get props =>
      [status, query, page, failure, actionFailure, submitting, savedNonce];
}

class WfhAllowancesBloc
    extends Bloc<WfhAllowancesEvent, WfhAllowancesState> {
  WfhAllowancesBloc(this._repo) : super(const WfhAllowancesState()) {
    on<WfhAllowancesLoadRequested>((e, emit) => _load(emit, e.query));
    on<WfhAllowancesSearchChanged>((e, emit) => _load(emit, e.query));
    on<WfhAllowancesSaved>(_onSave);
  }

  final EssRepository _repo;

  Future<void> _load(Emitter<WfhAllowancesState> emit, String query) async {
    emit(WfhAllowancesState(
        status: LoadStatus.loading,
        query: query,
        page: state.page,
        savedNonce: state.savedNonce));
    try {
      final page = await _repo.wfhAllowances(query: query);
      emit(WfhAllowancesState(
        status: page.rows.isEmpty ? LoadStatus.empty : LoadStatus.success,
        query: query,
        page: page,
        savedNonce: state.savedNonce,
      ));
    } on Failure catch (f) {
      emit(WfhAllowancesState(
          status: LoadStatus.failure,
          query: query,
          page: state.page,
          failure: f,
          savedNonce: state.savedNonce));
    }
  }

  Future<void> _onSave(
      WfhAllowancesSaved e, Emitter<WfhAllowancesState> emit) async {
    emit(WfhAllowancesState(
        status: state.status,
        query: state.query,
        page: state.page,
        submitting: true,
        savedNonce: state.savedNonce));
    try {
      await _repo.setWfhAllowance(
        employeeId: e.employeeId,
        enabled: e.enabled,
        monthlyLimitDays: e.monthlyLimitDays,
        note: e.note,
      );
      final page = await _repo.wfhAllowances(query: state.query);
      emit(WfhAllowancesState(
        status: page.rows.isEmpty ? LoadStatus.empty : LoadStatus.success,
        query: state.query,
        page: page,
        savedNonce: state.savedNonce + 1,
      ));
    } on Failure catch (f) {
      emit(WfhAllowancesState(
          status: state.status,
          query: state.query,
          page: state.page,
          actionFailure: f,
          savedNonce: state.savedNonce));
    }
  }
}

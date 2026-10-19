import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

sealed class EmployeePersonalEvent {
  const EmployeePersonalEvent();
}

class EmployeePersonalLoadRequested extends EmployeePersonalEvent {
  const EmployeePersonalLoadRequested();
}

class EmployeePersonalSubmitted extends EmployeePersonalEvent {
  const EmployeePersonalSubmitted(this.patch);
  final Map<String, dynamic> patch;
}

class EmployeePersonalState extends Equatable {
  const EmployeePersonalState({
    this.status = LoadStatus.initial,
    this.employee,
    this.personal,
    this.failure,
    this.saving = false,
    this.message,
    this.savedNonce = 0,
  });

  final LoadStatus status;
  final EmployeeCard? employee;
  final PersonalDetails? personal;
  final Failure? failure;
  final bool saving;
  final String? message;
  final int savedNonce;

  @override
  List<Object?> get props => [status, employee, personal, failure, saving, message, savedNonce];
}

class EmployeePersonalBloc extends Bloc<EmployeePersonalEvent, EmployeePersonalState> {
  EmployeePersonalBloc(this._repo, this.employeeId) : super(const EmployeePersonalState()) {
    on<EmployeePersonalLoadRequested>(_onLoad);
    on<EmployeePersonalSubmitted>(_onSubmit);
  }

  final EssRepository _repo;
  final String employeeId;

  Future<void> _onLoad(EmployeePersonalEvent e, Emitter<EmployeePersonalState> emit) async {
    emit(EmployeePersonalState(status: LoadStatus.loading, employee: state.employee, savedNonce: state.savedNonce));
    try {
      final r = await _repo.employeePersonal(employeeId);
      emit(EmployeePersonalState(
        status: LoadStatus.success,
        employee: r.employee,
        personal: r.personal,
        savedNonce: state.savedNonce,
      ));
    } on Failure catch (f) {
      emit(EmployeePersonalState(status: LoadStatus.failure, failure: f, savedNonce: state.savedNonce));
    }
  }

  Future<void> _onSubmit(EmployeePersonalSubmitted e, Emitter<EmployeePersonalState> emit) async {
    emit(EmployeePersonalState(
      status: state.status,
      employee: state.employee,
      personal: state.personal,
      saving: true,
      savedNonce: state.savedNonce,
    ));
    try {
      final r = await _repo.updateEmployeePersonal(employeeId, e.patch);
      emit(EmployeePersonalState(
        status: LoadStatus.success,
        employee: r.employee,
        personal: r.personal,
        savedNonce: state.savedNonce + 1,
      ));
    } on Failure catch (f) {
      emit(EmployeePersonalState(
        status: state.status,
        employee: state.employee,
        personal: state.personal,
        message: f.message,
        savedNonce: state.savedNonce,
      ));
    }
  }
}

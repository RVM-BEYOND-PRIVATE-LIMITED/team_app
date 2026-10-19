import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

sealed class PersonalEvent {
  const PersonalEvent();
}

class PersonalLoadRequested extends PersonalEvent {
  const PersonalLoadRequested();
}

class PersonalRefreshed extends PersonalEvent {
  const PersonalRefreshed();
}

/// Only the fields the employee may change (E9): blood group + emergency
/// contact. Date of birth and address are HR-only (403 `SENSITIVE_FIELD`).
class PersonalSubmitted extends PersonalEvent {
  const PersonalSubmitted({
    this.bloodGroup,
    this.emergencyName,
    this.emergencyRelation,
    this.emergencyPhone,
  });

  final String? bloodGroup;
  final String? emergencyName;
  final String? emergencyRelation;
  final String? emergencyPhone;
}

class PersonalState extends Equatable {
  const PersonalState({
    this.status = LoadStatus.initial,
    this.data,
    this.failure,
    this.saving = false,
    this.saveFailure,
    this.savedNonce = 0,
  });

  final LoadStatus status;
  final PersonalDetails? data;
  final Failure? failure;
  final bool saving;
  final Failure? saveFailure;

  /// Bumped on every successful save so the screen can show one SnackBar.
  final int savedNonce;

  PersonalState copyWith({
    LoadStatus? status,
    PersonalDetails? data,
    Failure? failure,
    bool? saving,
    Failure? saveFailure,
    int? savedNonce,
  }) =>
      PersonalState(
        status: status ?? this.status,
        data: data ?? this.data,
        failure: failure ?? this.failure,
        saving: saving ?? this.saving,
        saveFailure: saveFailure ?? this.saveFailure,
        savedNonce: savedNonce ?? this.savedNonce,
      );

  @override
  List<Object?> get props => [status, data, failure, saving, saveFailure, savedNonce];
}

class PersonalBloc extends Bloc<PersonalEvent, PersonalState> {
  PersonalBloc(this._repo) : super(const PersonalState()) {
    on<PersonalLoadRequested>(_onLoad);
    on<PersonalRefreshed>(_onLoad);
    on<PersonalSubmitted>(_onSubmit);
  }

  final EssRepository _repo;

  Future<void> _onLoad(PersonalEvent e, Emitter<PersonalState> emit) async {
    emit(PersonalState(status: LoadStatus.loading, data: state.data, savedNonce: state.savedNonce));
    try {
      final data = await _repo.personal();
      emit(PersonalState(status: LoadStatus.success, data: data, savedNonce: state.savedNonce));
    } on Failure catch (f) {
      emit(PersonalState(status: LoadStatus.failure, failure: f, savedNonce: state.savedNonce));
    }
  }

  Future<void> _onSubmit(PersonalSubmitted e, Emitter<PersonalState> emit) async {
    emit(state.copyWith(saving: true));
    final patch = <String, dynamic>{
      'blood_group': e.bloodGroup,
      'emergency_name': e.emergencyName,
      'emergency_relation': e.emergencyRelation,
      'emergency_phone': e.emergencyPhone,
    };
    try {
      final data = await _repo.updatePersonal(patch);
      emit(PersonalState(
        status: state.status,
        data: data,
        savedNonce: state.savedNonce + 1,
      ));
    } on Failure catch (f) {
      emit(state.copyWith(saving: false, saveFailure: f));
    }
  }
}

import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

/// D1/H6: the approvals Inbox and the decision.
sealed class ApprovalsEvent {
  const ApprovalsEvent();
}

class ApprovalsLoadRequested extends ApprovalsEvent {
  const ApprovalsLoadRequested();
}

class ApprovalsRefreshed extends ApprovalsEvent {
  const ApprovalsRefreshed();
}

class ApprovalsFiltered extends ApprovalsEvent {
  const ApprovalsFiltered(this.status);
  final String status;
}

class ApprovalDecided extends ApprovalsEvent {
  const ApprovalDecided({
    required this.family,
    required this.id,
    required this.decision,
    this.note,
    this.substituteFacultyId,
    this.classTiming,
  });
  final String family;
  final String id;
  final String decision; // approve | reject
  final String? note;

  /// Teaching leave at the Admin Manager stage: who covers the class and when.
  final String? substituteFacultyId;
  final String? classTiming;
}

class ApprovalArchived extends ApprovalsEvent {
  const ApprovalArchived({required this.family, required this.id});
  final String family;
  final String id;
}

class ApprovalsState extends Equatable {
  const ApprovalsState({
    this.status = LoadStatus.initial,
    this.filter = 'pending',
    this.inbox,
    this.failure,
    this.submitting = false,
    this.decidedNonce = 0,
    this.actionFailure,
  });

  final LoadStatus status;
  final String filter;
  final ApprovalInbox? inbox;
  final Failure? failure;
  final bool submitting;
  final int decidedNonce;
  final Failure? actionFailure;

  @override
  List<Object?> get props => [status, filter, inbox, failure, submitting, decidedNonce, actionFailure];
}

class ApprovalsBloc extends Bloc<ApprovalsEvent, ApprovalsState> {
  ApprovalsBloc(this._repo) : super(const ApprovalsState()) {
    on<ApprovalsLoadRequested>((_, emit) => _load(emit, state.filter));
    on<ApprovalsRefreshed>((_, emit) => _load(emit, state.filter));
    on<ApprovalsFiltered>((e, emit) => _load(emit, e.status));
    on<ApprovalDecided>(_onDecide);
    on<ApprovalArchived>(_onArchive);
  }

  final EssRepository _repo;

  Future<void> _load(Emitter<ApprovalsState> emit, String filter) async {
    emit(ApprovalsState(status: LoadStatus.loading, filter: filter, inbox: state.inbox, decidedNonce: state.decidedNonce));
    try {
      final inbox = await _repo.approvals(status: filter);
      emit(ApprovalsState(
        status: inbox.requests.isEmpty ? LoadStatus.empty : LoadStatus.success,
        filter: filter,
        inbox: inbox,
        decidedNonce: state.decidedNonce,
      ));
    } on Failure catch (f) {
      emit(ApprovalsState(status: LoadStatus.failure, filter: filter, failure: f, decidedNonce: state.decidedNonce));
    }
  }

  Future<void> _onDecide(ApprovalDecided e, Emitter<ApprovalsState> emit) async {
    emit(ApprovalsState(status: state.status, filter: state.filter, inbox: state.inbox, submitting: true, decidedNonce: state.decidedNonce));
    try {
      await _repo.decideRequest(
          family: e.family,
          id: e.id,
          decision: e.decision,
          note: e.note,
          substituteFacultyId: e.substituteFacultyId,
          classTiming: e.classTiming);
      final inbox = await _repo.approvals(status: state.filter);
      emit(ApprovalsState(
        status: inbox.requests.isEmpty ? LoadStatus.empty : LoadStatus.success,
        filter: state.filter,
        inbox: inbox,
        decidedNonce: state.decidedNonce + 1,
      ));
    } on Failure catch (f) {
      emit(ApprovalsState(status: state.status, filter: state.filter, inbox: state.inbox, actionFailure: f, decidedNonce: state.decidedNonce));
    }
  }

  Future<void> _onArchive(ApprovalArchived e, Emitter<ApprovalsState> emit) async {
    try {
      await _repo.archiveRequest(family: e.family, id: e.id);
      await _load(emit, state.filter);
    } on Failure catch (f) {
      emit(ApprovalsState(status: state.status, filter: state.filter, inbox: state.inbox, actionFailure: f, decidedNonce: state.decidedNonce));
    }
  }
}

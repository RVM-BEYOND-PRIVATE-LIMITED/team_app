import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

/// Phase 2B: my helpdesk tickets and the category list a raise form needs.
sealed class HelpdeskEvent {
  const HelpdeskEvent();
}

class HelpdeskLoadRequested extends HelpdeskEvent {
  const HelpdeskLoadRequested();
}

class HelpdeskRefreshed extends HelpdeskEvent {
  const HelpdeskRefreshed();
}

class HelpdeskFiltered extends HelpdeskEvent {
  const HelpdeskFiltered(this.status);
  final String? status;
}

class HelpdeskTicketRaised extends HelpdeskEvent {
  const HelpdeskTicketRaised({required this.category, required this.subject, required this.body, required this.anonymous});
  final String category;
  final String subject;
  final String body;
  final bool anonymous;
}

class HelpdeskState extends Equatable {
  const HelpdeskState({
    this.status = LoadStatus.initial,
    this.filter,
    this.categories = const [],
    this.tickets = const [],
    this.failure,
    this.submitting = false,
    this.actionFailure,
    this.actionNonce = 0,
  });

  final LoadStatus status;
  final String? filter;
  final List<HelpdeskCategory> categories;
  final List<HelpdeskTicket> tickets;
  final Failure? failure;
  final bool submitting;
  final Failure? actionFailure;
  final int actionNonce;

  @override
  List<Object?> get props => [status, filter, categories, tickets, failure, submitting, actionFailure, actionNonce];
}

class HelpdeskBloc extends Bloc<HelpdeskEvent, HelpdeskState> {
  HelpdeskBloc(this._repo) : super(const HelpdeskState()) {
    on<HelpdeskLoadRequested>((_, emit) => _load(emit, state.filter));
    on<HelpdeskRefreshed>((_, emit) => _load(emit, state.filter));
    on<HelpdeskFiltered>((e, emit) => _load(emit, e.status));
    on<HelpdeskTicketRaised>(_onRaise);
  }

  final EssRepository _repo;

  Future<void> _load(Emitter<HelpdeskState> emit, String? filter) async {
    emit(HelpdeskState(status: LoadStatus.loading, filter: filter, categories: state.categories, tickets: state.tickets, actionNonce: state.actionNonce));
    try {
      final settings = state.categories.isEmpty ? await _repo.helpdeskCategories() : null;
      final tickets = await _repo.myTickets(status: filter);
      emit(HelpdeskState(
        status: tickets.isEmpty ? LoadStatus.empty : LoadStatus.success,
        filter: filter,
        categories: settings?.categories ?? state.categories,
        tickets: tickets,
        actionNonce: state.actionNonce,
      ));
    } on Failure catch (f) {
      emit(HelpdeskState(status: LoadStatus.failure, filter: filter, categories: state.categories, tickets: state.tickets, failure: f));
    }
  }

  Future<void> _onRaise(HelpdeskTicketRaised e, Emitter<HelpdeskState> emit) async {
    emit(HelpdeskState(status: state.status, filter: state.filter, categories: state.categories, tickets: state.tickets, submitting: true, actionNonce: state.actionNonce));
    try {
      await _repo.raiseTicket(category: e.category, subject: e.subject, body: e.body, anonymous: e.anonymous);
      emit(HelpdeskState(status: state.status, filter: state.filter, categories: state.categories, tickets: state.tickets, actionNonce: state.actionNonce + 1));
      await _load(emit, state.filter);
    } on Failure catch (f) {
      emit(HelpdeskState(status: state.status, filter: state.filter, categories: state.categories, tickets: state.tickets, actionFailure: f));
    }
  }
}

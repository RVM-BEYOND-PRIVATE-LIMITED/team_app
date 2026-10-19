import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/repositories/auth_repository.dart';

// ── events ──────────────────────────────────────────────────────────────
sealed class ForgotEvent {
  const ForgotEvent();
}

class ForgotRequested extends ForgotEvent {
  const ForgotRequested(this.identifier);
  final String identifier;
}

class ForgotConfirmed extends ForgotEvent {
  const ForgotConfirmed({required this.identifier, required this.code, required this.newPassword});
  final String identifier;
  final String code;
  final String newPassword;
}

class ForgotReset extends ForgotEvent {
  const ForgotReset();
}

// ── state ───────────────────────────────────────────────────────────────
class ForgotState extends Equatable {
  const ForgotState({this.submitting = false, this.codeSent = false, this.done = false, this.message, this.error});

  final bool submitting;
  final bool codeSent;
  final bool done;
  final String? message;
  final String? error;

  ForgotState copyWith({
    bool? submitting,
    bool? codeSent,
    bool? done,
    String? message,
    String? error,
    bool clearError = false,
  }) =>
      ForgotState(
        submitting: submitting ?? this.submitting,
        codeSent: codeSent ?? this.codeSent,
        done: done ?? this.done,
        message: message ?? this.message,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [submitting, codeSent, done, message, error];
}

/// Code-based password reset — POST /users/forgot-password (+ /confirm). The
/// two-step, code-proven flow (never the retired username+phone reset).
class ForgotPasswordBloc extends Bloc<ForgotEvent, ForgotState> {
  ForgotPasswordBloc(this._repo) : super(const ForgotState()) {
    on<ForgotRequested>(_onRequest);
    on<ForgotConfirmed>(_onConfirm);
    on<ForgotReset>((e, emit) => emit(const ForgotState()));
  }

  final AuthRepository _repo;

  Future<void> _onRequest(ForgotRequested e, Emitter<ForgotState> emit) async {
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      final message = await _repo.forgotPasswordRequest(e.identifier);
      emit(state.copyWith(
        submitting: false,
        codeSent: true,
        message: message ?? 'If that account has a verified email, a code has been sent to it.',
      ));
    } on Failure catch (f) {
      emit(state.copyWith(submitting: false, error: f.message));
    }
  }

  Future<void> _onConfirm(ForgotConfirmed e, Emitter<ForgotState> emit) async {
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      await _repo.forgotPasswordConfirm(identifier: e.identifier, code: e.code, newPassword: e.newPassword);
      emit(state.copyWith(submitting: false, done: true));
    } on Failure catch (f) {
      emit(state.copyWith(submitting: false, error: f.message));
    }
  }
}

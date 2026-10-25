import 'dart:io';

import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/me_repository.dart';
import '../../../domain/models.dart';

// ── events ──────────────────────────────────────────────────────────────
sealed class AccountActionEvent {
  const AccountActionEvent();
}

class AccountChangePassword extends AccountActionEvent {
  const AccountChangePassword({required this.oldPassword, required this.newPassword});
  final String oldPassword;
  final String newPassword;
}

class AccountRequestEmail extends AccountActionEvent {
  const AccountRequestEmail({required this.email, required this.password});
  final String email;
  final String password;
}

class AccountConfirmEmail extends AccountActionEvent {
  const AccountConfirmEmail(this.code);
  final String code;
}

class AccountRequestPhone extends AccountActionEvent {
  const AccountRequestPhone({required this.phoneNumber, required this.password});
  final String phoneNumber;
  final String password;
}

class AccountConfirmPhone extends AccountActionEvent {
  const AccountConfirmPhone(this.code);
  final String code;
}

class AccountRequestTwoFactor extends AccountActionEvent {
  const AccountRequestTwoFactor();
}

class AccountEnableTwoFactor extends AccountActionEvent {
  const AccountEnableTwoFactor(this.code);
  final String code;
}

class AccountDisableTwoFactor extends AccountActionEvent {
  const AccountDisableTwoFactor(this.password);
  final String password;
}

class AccountUploadPhoto extends AccountActionEvent {
  const AccountUploadPhoto({required this.bytes, required this.filename});
  final List<int> bytes;
  final String filename;
}

class AccountRemovePhoto extends AccountActionEvent {
  const AccountRemovePhoto();
}

class AccountActionCleared extends AccountActionEvent {
  const AccountActionCleared();
}

// ── state ───────────────────────────────────────────────────────────────
class AccountActionState extends Equatable {
  const AccountActionState({
    this.status = WriteStatus.idle,
    this.error,
    this.message,
    this.profile,
    this.codeSent = false,
  });

  final WriteStatus status;
  final String? error;
  final String? message;
  final TeamProfile? profile;

  /// True after an email/phone change was requested (a code is on its way).
  final bool codeSent;

  AccountActionState copyWith({
    WriteStatus? status,
    String? error,
    String? message,
    TeamProfile? profile,
    bool? codeSent,
    bool clearError = false,
  }) =>
      AccountActionState(
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        message: message ?? this.message,
        profile: profile ?? this.profile,
        codeSent: codeSent ?? this.codeSent,
      );

  @override
  List<Object?> get props => [status, error, message, profile, codeSent];
}

/// One-shot account/security writes (`/api/me/*`). UI reads [AccountActionState]
/// and reacts to [WriteStatus.success] / [WriteStatus.failure].
class AccountActionBloc extends Bloc<AccountActionEvent, AccountActionState> {
  AccountActionBloc(this._repo) : super(const AccountActionState()) {
    on<AccountChangePassword>(_changePassword);
    on<AccountRequestEmail>(_requestEmail);
    on<AccountConfirmEmail>(_confirmEmail);
    on<AccountRequestPhone>(_requestPhone);
    on<AccountConfirmPhone>(_confirmPhone);
    on<AccountRequestTwoFactor>(_requestTwoFactor);
    on<AccountEnableTwoFactor>(_enableTwoFactor);
    on<AccountDisableTwoFactor>(_disableTwoFactor);
    on<AccountUploadPhoto>(_uploadPhoto);
    on<AccountRemovePhoto>(_removePhoto);
    on<AccountActionCleared>((e, emit) => emit(const AccountActionState()));
  }

  final MeRepository _repo;

  Future<void> _run(
    Emitter<AccountActionState> emit,
    Future<TeamProfile?> Function() action, {
    String? message,
    bool codeSent = false,
  }) async {
    emit(state.copyWith(status: WriteStatus.submitting, clearError: true));
    try {
      final profile = await action();
      emit(state.copyWith(status: WriteStatus.success, profile: profile, message: message, codeSent: codeSent));
    } on Failure catch (f) {
      emit(state.copyWith(status: WriteStatus.failure, error: f.message));
    } on DioException catch (e) {
      // A raw Dio error that bypassed the repository guard (connectivity
      // probe, DNS outside Dio). Staff read the typed line, never the raw
      // `SocketException: Failed host lookup …` text from issue13.
      emit(state.copyWith(
          status: WriteStatus.failure,
          error: Failure.fromDio(e).message));
    } on SocketException {
      emit(state.copyWith(
          status: WriteStatus.failure,
          error: const NoConnectionFailure().message));
    } catch (_) {
      // Never leak raw `e.toString()` to the dialog (issue13). Unknown
      // errors get the friendly line; raw detail stays in the log.
      emit(state.copyWith(
          status: WriteStatus.failure,
          error: const UnknownFailure('Could not complete that. Try again.')
              .message));
    }
  }

  Future<void> _changePassword(AccountChangePassword e, Emitter<AccountActionState> emit) => _run(
        emit,
        () async {
          await _repo.changePassword(oldPassword: e.oldPassword, newPassword: e.newPassword);
          return null;
        },
        message: 'Password changed.',
      );

  Future<void> _requestEmail(AccountRequestEmail e, Emitter<AccountActionState> emit) => _run(
        emit,
        () async {
          await _repo.requestEmailChange(email: e.email, password: e.password);
          return null;
        },
        message: 'A code was sent — enter it to confirm the new email.',
        codeSent: true,
      );

  Future<void> _confirmEmail(AccountConfirmEmail e, Emitter<AccountActionState> emit) =>
      _run(emit, () => _repo.confirmEmailChange(e.code), message: 'Email updated.');

  Future<void> _requestPhone(AccountRequestPhone e, Emitter<AccountActionState> emit) => _run(
        emit,
        () async {
          await _repo.requestPhoneChange(phoneNumber: e.phoneNumber, password: e.password);
          return null;
        },
        message: 'A code was sent by SMS — enter it to confirm the new number.',
        codeSent: true,
      );

  Future<void> _confirmPhone(AccountConfirmPhone e, Emitter<AccountActionState> emit) =>
      _run(emit, () => _repo.confirmPhoneChange(e.code), message: 'Phone number updated.');

  Future<void> _requestTwoFactor(AccountRequestTwoFactor e, Emitter<AccountActionState> emit) => _run(
        emit,
        () async {
          await _repo.requestTwoFactorEnable();
          return null;
        },
        message: 'A code was sent to your verified email — enter it to switch on two-factor.',
        codeSent: true,
      );

  Future<void> _enableTwoFactor(AccountEnableTwoFactor e, Emitter<AccountActionState> emit) =>
      _run(emit, () => _repo.enableTwoFactor(e.code), message: 'Two-factor is on.');

  Future<void> _disableTwoFactor(AccountDisableTwoFactor e, Emitter<AccountActionState> emit) =>
      _run(emit, () => _repo.disableTwoFactor(e.password), message: 'Two-factor is off.');

  Future<void> _uploadPhoto(AccountUploadPhoto e, Emitter<AccountActionState> emit) =>
      _run(emit, () => _repo.uploadPhoto(e.bytes, e.filename), message: 'Photo updated.');

  Future<void> _removePhoto(AccountRemovePhoto e, Emitter<AccountActionState> emit) =>
      _run(emit, () => _repo.removePhoto(), message: 'Photo removed.');
}

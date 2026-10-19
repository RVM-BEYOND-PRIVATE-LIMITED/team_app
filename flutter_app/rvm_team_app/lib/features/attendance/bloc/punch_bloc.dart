import 'dart:async';

import 'package:core_auth/core_auth.dart';
import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/location_service.dart';
import '../../../data/repositories/ess_repository.dart';
import '../../../data/repositories/my_attendance_repository.dart';
import '../../../domain/attendance_models.dart';

sealed class PunchEvent {
  const PunchEvent();
}

class PunchLoadRequested extends PunchEvent {
  const PunchLoadRequested();
}

class PunchRefreshed extends PunchEvent {
  const PunchRefreshed();
}

class PunchRequested extends PunchEvent {
  const PunchRequested(this.kind); // in | out
  final String kind;
}

class PunchRemarkRequested extends PunchEvent {
  const PunchRemarkRequested(this.remarks);
  final String remarks;
}

/// Choose a new attendance password (first-time password, or none yet). The
/// server returns a fresh session token that replaces the current one.
class PunchSetPasswordRequested extends PunchEvent {
  const PunchSetPasswordRequested(this.password);
  final String password;
}

class PunchState extends Equatable {
  const PunchState({
    this.status = LoadStatus.initial,
    this.data,
    this.failure,
    this.punching = false,
    this.message,
    this.lastPunch,
    this.remarksNonce = 0,
  });

  final LoadStatus status;
  final MyAttendance? data;
  final Failure? failure;
  final bool punching;
  final String? message;
  final PunchAccepted? lastPunch;
  final int remarksNonce;

  PunchState copyWith({
    LoadStatus? status,
    MyAttendance? data,
    Failure? failure,
    bool? punching,
    String? message,
    bool clearMessage = false,
    PunchAccepted? lastPunch,
    bool clearLastPunch = false,
    int? remarksNonce,
  }) =>
      PunchState(
        status: status ?? this.status,
        data: data ?? this.data,
        failure: failure,
        punching: punching ?? this.punching,
        message: clearMessage ? null : (message ?? this.message),
        lastPunch: clearLastPunch ? null : (lastPunch ?? this.lastPunch),
        remarksNonce: remarksNonce ?? this.remarksNonce,
      );

  @override
  List<Object?> get props => [status, data, failure, punching, message, lastPunch, remarksNonce];
}

class PunchBloc extends Bloc<PunchEvent, PunchState> {
  PunchBloc(this._repo, this._ess, this._session) : super(const PunchState()) {
    on<PunchLoadRequested>(_onLoad);
    on<PunchRefreshed>(_onLoad);
    on<PunchRequested>(_onPunch);
    on<PunchRemarkRequested>(_onRemark);
    on<PunchSetPasswordRequested>(_onSetPassword);
  }

  final MyAttendanceRepository _repo;
  final EssRepository _ess;
  final AuthSession _session;

  Timer? _pingTimer;

  @override
  Future<void> close() {
    _pingTimer?.cancel();
    return super.close();
  }

  Future<void> _onLoad(PunchEvent e, Emitter<PunchState> emit) async {
    emit(state.copyWith(status: LoadStatus.loading));
    try {
      final data = await _repo.myAttendance();
      emit(state.copyWith(status: LoadStatus.success, data: data));
      _syncPing(data);
    } on Failure catch (f) {
      emit(state.copyWith(status: LoadStatus.failure, failure: f));
    }
  }

  Future<void> _onPunch(PunchRequested e, Emitter<PunchState> emit) async {
    emit(state.copyWith(punching: true, clearMessage: true, clearLastPunch: true));
    try {
      final fix = await _repo.fix();
      if (fix.mocked) {
        // Refuse on the phone and report the attempt to HR (decision 6, B14).
        unawaited(_reportMocked(fix));
        emit(state.copyWith(
          punching: false,
          message: 'This phone reported a mocked location. The punch was not sent, and HR has been told.',
        ));
        return;
      }
      final accepted = await _repo.punch(kind: e.kind, fix: fix);
      final data = await _repo.myAttendance();
      emit(state.copyWith(status: LoadStatus.success, data: data, punching: false, lastPunch: accepted));
      _syncPing(data);
    } on LocationException catch (ex) {
      emit(state.copyWith(punching: false, message: ex.message));
    } on Failure catch (f) {
      emit(state.copyWith(punching: false, message: f.message));
    }
  }

  Future<void> _onRemark(PunchRemarkRequested e, Emitter<PunchState> emit) async {
    final day = state.data?.today?.day;
    if (day == null) return;
    try {
      await _repo.saveRemark(day: day, remarks: e.remarks);
      final data = await _repo.myAttendance();
      emit(state.copyWith(
        data: data,
        message: e.remarks.trim().isEmpty ? 'Remark removed.' : 'Remark saved.',
        remarksNonce: state.remarksNonce + 1,
      ));
    } on Failure catch (f) {
      emit(state.copyWith(message: f.message));
    }
  }

  Future<void> _onSetPassword(PunchSetPasswordRequested e, Emitter<PunchState> emit) async {
    emit(state.copyWith(punching: true, clearMessage: true));
    try {
      final token = await _repo.setAttendancePassword(e.password);
      if (token.isNotEmpty) await _session.saveSchedulerSession(token: token);
      final data = await _repo.myAttendance();
      emit(state.copyWith(
        status: LoadStatus.success,
        data: data,
        punching: false,
        message: 'Password set. You can punch now.',
      ));
    } on Failure catch (f) {
      emit(state.copyWith(punching: false, message: f.message));
    }
  }

  Future<void> _reportMocked(LocationFix fix) async {
    try {
      await _ess.reportMockLocation({
        'kind': 'punch',
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        'accuracy_m': fix.accuracyM,
      });
    } catch (_) {
      // The report is best-effort; the punch is already refused.
    }
  }

  /// One fix every 2 minutes while punched in and not yet done (B4/ping).
  void _syncPing(MyAttendance data) {
    final active = data.linked && (data.today?.punchedIn ?? false) && !(data.today?.done ?? false);
    if (active && _pingTimer == null) {
      _pingTimer = Timer.periodic(const Duration(minutes: 2), (_) => _ping());
    } else if (!active) {
      _pingTimer?.cancel();
      _pingTimer = null;
    }
  }

  Future<void> _ping() async {
    try {
      final fix = await _repo.fix();
      if (fix.mocked) return;
      await _repo.ping(fix);
    } catch (_) {
      // Pings are silent: a missed ping is not an error the person must see.
    }
  }
}

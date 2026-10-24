import 'dart:async';
import 'dart:math' as math;

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
  const PunchLoadRequested({this.withDistance = false});

  /// The Home card asks for the distance to the geofence as part of the load.
  /// The full punch screen does not need to take a fix until the person punches.
  final bool withDistance;
}

class PunchRefreshed extends PunchEvent {
  const PunchRefreshed();
}

/// Re-read the phone's position and recompute the distance to the branch
/// geofence (the Home card's distance line and its retry action).
class PunchDistanceRequested extends PunchEvent {
  const PunchDistanceRequested();
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
    this.distanceMeters,
    this.accuracyMeters,
    this.allowedRadiusMeters,
    this.distanceLoading = false,
    this.distanceError,
  });

  final LoadStatus status;
  final MyAttendance? data;
  final Failure? failure;
  final bool punching;
  final String? message;
  final PunchAccepted? lastPunch;
  final int remarksNonce;

  /// The last measured distance from the phone to the branch's geofence centre,
  /// and the radius the server will judge the punch against.
  final double? distanceMeters;
  final double? accuracyMeters;
  final double? allowedRadiusMeters;
  final bool distanceLoading;
  final String? distanceError;

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
    double? distanceMeters,
    double? accuracyMeters,
    double? allowedRadiusMeters,
    bool? distanceLoading,
    String? distanceError,
    bool clearDistance = false,
    bool clearDistanceError = false,
  }) =>
      PunchState(
        status: status ?? this.status,
        data: data ?? this.data,
        failure: failure,
        punching: punching ?? this.punching,
        message: clearMessage ? null : (message ?? this.message),
        lastPunch: clearLastPunch ? null : (lastPunch ?? this.lastPunch),
        remarksNonce: remarksNonce ?? this.remarksNonce,
        distanceMeters:
            clearDistance ? null : (distanceMeters ?? this.distanceMeters),
        accuracyMeters:
            clearDistance ? null : (accuracyMeters ?? this.accuracyMeters),
        allowedRadiusMeters: clearDistance
            ? null
            : (allowedRadiusMeters ?? this.allowedRadiusMeters),
        distanceLoading: distanceLoading ?? this.distanceLoading,
        distanceError:
            clearDistanceError ? null : (distanceError ?? this.distanceError),
      );

  @override
  List<Object?> get props => [
        status,
        data,
        failure,
        punching,
        message,
        lastPunch,
        remarksNonce,
        distanceMeters,
        accuracyMeters,
        allowedRadiusMeters,
        distanceLoading,
        distanceError,
      ];
}

class PunchBloc extends Bloc<PunchEvent, PunchState> {
  PunchBloc(this._repo, this._ess, this._session) : super(const PunchState()) {
    on<PunchLoadRequested>(_onLoad);
    on<PunchRefreshed>(_onLoad);
    on<PunchRequested>(_onPunch);
    on<PunchDistanceRequested>(_onDistance);
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
    final result = await _repo.myAttendanceSafe();
    if (result.failure != null || result.data == null) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        failure: result.failure ?? const UnknownFailure(),
      ));
      return;
    }
    final data = result.data!;
    emit(state.copyWith(status: LoadStatus.success, data: data));
    _syncPing(data);
    if (e is PunchLoadRequested && e.withDistance) {
      await _refreshDistance(emit, data);
    }
  }

  Future<void> _onDistance(
      PunchDistanceRequested e, Emitter<PunchState> emit) async {
    final data = state.data;
    if (data == null) return;
    await _refreshDistance(emit, data);
  }

  /// The distance is informative only: the server still judges the punch. A
  /// missing geofence or a refused location permission must not block the
  /// button, so the note explains what is wrong instead.
  Future<void> _refreshDistance(
      Emitter<PunchState> emit, MyAttendance data) async {
    final branch = data.branch;
    if (!data.linked ||
        branch == null ||
        !branch.configured ||
        branch.latitude == null ||
        branch.longitude == null ||
        branch.radiusM == null) {
      emit(state.copyWith(
        distanceLoading: false,
        clearDistance: true,
        clearDistanceError: true,
      ));
      return;
    }
    emit(state.copyWith(distanceLoading: true, clearDistanceError: true));
    try {
      final fix = await _repo.fix();
      _emitDistance(emit, data, fix);
    } on LocationException catch (ex) {
      emit(state.copyWith(distanceLoading: false, distanceError: ex.message));
    } on Object {
      emit(state.copyWith(
          distanceLoading: false,
          distanceError: 'Could not read your location. Tap to retry.'));
    }
  }

  void _emitDistance(
      Emitter<PunchState> emit, MyAttendance data, LocationFix fix) {
    final branch = data.branch;
    if (branch == null ||
        branch.latitude == null ||
        branch.longitude == null ||
        branch.radiusM == null) {
      return;
    }
    emit(state.copyWith(
      distanceLoading: false,
      distanceMeters: _distanceMeters(
        fix.latitude,
        fix.longitude,
        branch.latitude!,
        branch.longitude!,
      ),
      accuracyMeters: fix.accuracyM,
      allowedRadiusMeters: branch.radiusM,
      clearDistanceError: true,
    ));
  }

  static double _distanceMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadius * math.asin(math.sqrt(a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  Future<void> _onPunch(PunchRequested e, Emitter<PunchState> emit) async {
    emit(state.copyWith(
        punching: true, clearMessage: true, clearLastPunch: true));
    try {
      final fix = await _repo.fix();
      if (fix.mocked) {
        // Refuse on the phone and report the attempt to HR (decision 6, B14).
        unawaited(_reportMocked(fix));
        emit(state.copyWith(
          punching: false,
          message:
              'This phone reported a mocked location. The punch was not sent, and HR has been told.',
        ));
        return;
      }
      final accepted = await _repo.punch(kind: e.kind, fix: fix);
      final data = await _repo.myAttendance();
      emit(state.copyWith(
          status: LoadStatus.success,
          data: data,
          punching: false,
          lastPunch: accepted));
      _emitDistance(emit, data, fix);
      _syncPing(data);
    } on LocationException catch (ex) {
      emit(state.copyWith(punching: false, message: ex.message));
    } on Failure catch (f) {
      emit(state.copyWith(punching: false, message: f.message));
    } on Object {
      // A plugin error or an unexpected parse must not leave `punching` true,
      // which would disable the punch button until the screen is reopened.
      emit(state.copyWith(
          punching: false,
          message: 'The punch could not be completed. Please try again.'));
    }
  }

  Future<void> _onRemark(
      PunchRemarkRequested e, Emitter<PunchState> emit) async {
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

  Future<void> _onSetPassword(
      PunchSetPasswordRequested e, Emitter<PunchState> emit) async {
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
    } on Object {
      emit(state.copyWith(
          punching: false,
          message: 'The password could not be saved. Please try again.'));
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
    final active = data.linked &&
        (data.today?.punchedIn ?? false) &&
        !(data.today?.done ?? false);
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

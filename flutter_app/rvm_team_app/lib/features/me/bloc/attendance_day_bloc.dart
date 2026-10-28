import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../data/repositories/my_attendance_repository.dart';
import '../../../domain/attendance_models.dart';
import '../../../domain/ess_models.dart';

sealed class AttendanceDayEvent {
  const AttendanceDayEvent();
}

class AttendanceDayLoadRequested extends AttendanceDayEvent {
  const AttendanceDayLoadRequested();
}

class AttendanceDayRefreshed extends AttendanceDayEvent {
  const AttendanceDayRefreshed();
}

/// Report a location the phone refused to punch with (B14). `kind` is fixed to
/// `punch` by the contract.
class MockLocationReportSubmitted extends AttendanceDayEvent {
  const MockLocationReportSubmitted({
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.provider,
    this.appVersion,
  });

  final double? latitude;
  final double? longitude;
  final double? accuracyM;
  final String? provider;
  final String? appVersion;
}

class AttendanceDayState extends Equatable {
  const AttendanceDayState({
    this.status = LoadStatus.initial,
    this.day,
    this.failure,
    this.reporting = false,
    this.reportFailure,
    this.reportedNonce = 0,
    this.currentMonth,
    this.previousMonth,
    this.logsLoading = false,
    this.logFailure,
  });

  final LoadStatus status;
  final AttendanceDay? day;
  final Failure? failure;
  final bool reporting;
  final Failure? reportFailure;
  final int reportedNonce;
  final MyAttendance? currentMonth;
  final MyAttendance? previousMonth;
  final bool logsLoading;
  final Failure? logFailure;

  @override
  List<Object?> get props => [
        status,
        day,
        failure,
        reporting,
        reportFailure,
        reportedNonce,
        currentMonth,
        previousMonth,
        logsLoading,
        logFailure,
      ];
}

class AttendanceDayBloc extends Bloc<AttendanceDayEvent, AttendanceDayState> {
  AttendanceDayBloc(this._repo, this._attendance)
      : super(const AttendanceDayState()) {
    on<AttendanceDayLoadRequested>(_onLoad);
    on<AttendanceDayRefreshed>(_onLoad);
    on<MockLocationReportSubmitted>(_onReport);
  }

  final EssRepository _repo;
  final MyAttendanceRepository _attendance;

  static String today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  Future<void> _onLoad(
      AttendanceDayEvent e, Emitter<AttendanceDayState> emit) async {
    emit(AttendanceDayState(
      status: LoadStatus.loading,
      day: state.day,
      reportedNonce: state.reportedNonce,
      currentMonth: state.currentMonth,
      previousMonth: state.previousMonth,
      logsLoading: true,
    ));
    try {
      final day = await _repo.attendanceDay(today());
      final now = DateTime.now();
      final previous = DateTime(now.year, now.month - 1);
      final results = await Future.wait([
        _attendance.myAttendanceSafe(month: monthKey(now)),
        _attendance.myAttendanceSafe(month: monthKey(previous)),
      ]);
      emit(AttendanceDayState(
        status: LoadStatus.success,
        day: day,
        reportedNonce: state.reportedNonce,
        currentMonth: results[0].data,
        previousMonth: results[1].data,
        logFailure: results[0].failure ?? results[1].failure,
      ));
    } on Failure catch (f) {
      emit(AttendanceDayState(
        status: LoadStatus.failure,
        failure: f,
        reportedNonce: state.reportedNonce,
        currentMonth: state.currentMonth,
        previousMonth: state.previousMonth,
      ));
    }
  }

  Future<void> _onReport(
      MockLocationReportSubmitted e, Emitter<AttendanceDayState> emit) async {
    emit(AttendanceDayState(
      status: state.status,
      day: state.day,
      reporting: true,
      reportedNonce: state.reportedNonce,
      currentMonth: state.currentMonth,
      previousMonth: state.previousMonth,
      logsLoading: state.logsLoading,
      logFailure: state.logFailure,
    ));
    try {
      await _repo.reportMockLocation({
        'kind': 'punch',
        if (e.latitude != null) 'latitude': e.latitude,
        if (e.longitude != null) 'longitude': e.longitude,
        if (e.accuracyM != null) 'accuracy_m': e.accuracyM,
        if (e.provider != null) 'provider': e.provider,
        if (e.appVersion != null) 'app_version': e.appVersion,
      });
      emit(AttendanceDayState(
        status: state.status,
        day: state.day,
        reportedNonce: state.reportedNonce + 1,
        currentMonth: state.currentMonth,
        previousMonth: state.previousMonth,
        logsLoading: state.logsLoading,
        logFailure: state.logFailure,
      ));
    } on Failure catch (f) {
      emit(AttendanceDayState(
        status: state.status,
        day: state.day,
        reportFailure: f,
        reportedNonce: state.reportedNonce,
        currentMonth: state.currentMonth,
        previousMonth: state.previousMonth,
        logsLoading: state.logsLoading,
        logFailure: state.logFailure,
      ));
    }
  }
}

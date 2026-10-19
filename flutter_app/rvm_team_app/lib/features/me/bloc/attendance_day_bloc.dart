import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
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
  });

  final LoadStatus status;
  final AttendanceDay? day;
  final Failure? failure;
  final bool reporting;
  final Failure? reportFailure;
  final int reportedNonce;

  @override
  List<Object?> get props => [status, day, failure, reporting, reportFailure, reportedNonce];
}

class AttendanceDayBloc extends Bloc<AttendanceDayEvent, AttendanceDayState> {
  AttendanceDayBloc(this._repo) : super(const AttendanceDayState()) {
    on<AttendanceDayLoadRequested>(_onLoad);
    on<AttendanceDayRefreshed>(_onLoad);
    on<MockLocationReportSubmitted>(_onReport);
  }

  final EssRepository _repo;

  static String today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _onLoad(AttendanceDayEvent e, Emitter<AttendanceDayState> emit) async {
    emit(AttendanceDayState(status: LoadStatus.loading, day: state.day, reportedNonce: state.reportedNonce));
    try {
      final day = await _repo.attendanceDay(today());
      emit(AttendanceDayState(status: LoadStatus.success, day: day, reportedNonce: state.reportedNonce));
    } on Failure catch (f) {
      emit(AttendanceDayState(status: LoadStatus.failure, failure: f, reportedNonce: state.reportedNonce));
    }
  }

  Future<void> _onReport(MockLocationReportSubmitted e, Emitter<AttendanceDayState> emit) async {
    emit(AttendanceDayState(status: state.status, day: state.day, reporting: true, reportedNonce: state.reportedNonce));
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
      ));
    } on Failure catch (f) {
      emit(AttendanceDayState(
        status: state.status,
        day: state.day,
        reportFailure: f,
        reportedNonce: state.reportedNonce,
      ));
    }
  }
}

import 'package:core_network/core_network.dart';

import '../../domain/attendance_models.dart';
import '../connectivity_guard.dart';
import '../datasources/my_attendance_remote_data_source.dart';
import '../location_service.dart';

/// The self punch flow: read the punch screen, take a fix, get a challenge and
/// punch (tasks B2-B7, B11), send pings while punched in, and save a remark.
class MyAttendanceRepository with ConnectivityGuard {
  MyAttendanceRepository({
    required MyAttendanceRemoteDataSource remote,
    required LocationService location,
    required this.connectivity,
  })  : _remote = remote,
        _location = location;

  final MyAttendanceRemoteDataSource _remote;
  final LocationService _location;

  @override
  final ConnectivityService connectivity;

  Future<MyAttendance> myAttendance({String? month}) async {
    await ensureOnline();
    return _remote.myAttendance(month: month);
  }

  Future<({MyAttendance? data, Failure? failure})> myAttendanceSafe(
      {String? month}) async {
    try {
      await ensureOnline();
      return await _remote.myAttendanceSafe(month: month);
    } on Failure catch (f) {
      return (data: null, failure: f);
    } catch (_) {
      return (
        data: null,
        failure: const UnknownFailure('Could not load your attendance.'),
      );
    }
  }

  /// Take one fix and return it. Returns `null` when no fix arrives within the
  /// timeout (indoors/background); throws [LocationException] only for a
  /// permission or GPS-service problem. A mocked fix comes back with
  /// `mocked: true` so the caller can report it to HR and stop.
  Future<LocationFix?> fix() => _location.current();

  /// Punch with an already-taken fix (so the caller can check `mocked` first).
  Future<PunchAccepted> punch({
    required String kind,
    required LocationFix fix,
    String? note,
  }) async {
    await ensureOnline();
    final challenge = await _remote.challenge();
    return _remote.punch(
      kind: kind,
      nonce: challenge.nonce,
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracyM: fix.accuracyM,
      clientAt: DateTime.now(),
      note: note,
    );
  }

  Future<void> ping(LocationFix fix) async {
    await ensureOnline();
    await _remote.ping(
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyM: fix.accuracyM);
  }

  Future<void> saveRemark({required String day, String? remarks}) async {
    await ensureOnline();
    await _remote.saveRemark(day: day, remarks: remarks);
  }

  /// Returns the fresh session token the caller must persist (it replaces the
  /// current one; older sessions of this login stop working).
  Future<String> setAttendancePassword(String password) async {
    await ensureOnline();
    return _remote.setAttendancePassword(password);
  }
}

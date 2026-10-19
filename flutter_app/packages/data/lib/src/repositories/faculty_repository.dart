import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/faculty_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff faculty / HR (Scheduler). The [roster] merges the base list with the
/// active-students + total-students metric endpoints; the two metric calls are
/// non-critical (their failure just leaves those counts null).
class FacultyRepository with ConnectivityGuard {
  FacultyRepository({required FacultyRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final FacultyRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<Faculty>> roster({String? locationId}) async {
    await ensureOnline();
    final list = await _remote.list(locationId: locationId);
    Map<String, int> active = const {};
    Map<String, int> totals = const {};
    try {
      active = await _remote.activeStudents(locationId: locationId);
    } on Failure {
      active = const {};
    }
    try {
      totals = await _remote.studentCounts(locationId: locationId);
    } on Failure {
      totals = const {};
    }
    return [
      for (final f in list) f.withMetrics(active: active[f.id], total: totals[f.id]),
    ];
  }

  Future<FacultyTotalStudents> totalStudents(String facultyId) async {
    await ensureOnline();
    return _remote.totalStudents(facultyId);
  }

  Future<Faculty> create(FacultyDraft draft) async {
    await ensureOnline();
    return _remote.create(draft);
  }

  Future<Faculty> update(String id, FacultyUpdate update) async {
    await ensureOnline();
    return _remote.update(id, update);
  }

  Future<void> delete(String id) async {
    await ensureOnline();
    return _remote.delete(id);
  }

  Future<List<FacultyAvailability>> availability(String facultyId) async {
    await ensureOnline();
    return _remote.availability(facultyId);
  }

  Future<List<FacultyAvailability>> setAvailability({
    required String facultyId,
    required List<FacultyAvailability> slots,
  }) async {
    await ensureOnline();
    return _remote.setAvailability(facultyId: facultyId, slots: slots);
  }
}

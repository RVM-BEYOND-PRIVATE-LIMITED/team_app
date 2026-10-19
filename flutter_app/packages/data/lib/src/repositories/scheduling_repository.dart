import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/scheduling_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff faculty-scheduling helpers (Scheduler). Connectivity-guarded
/// pass-throughs — the free-slot finder + the faculty suggester.
class SchedulingRepository with ConnectivityGuard {
  SchedulingRepository({required SchedulingRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final SchedulingRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<FacultyFreeSlots>> freeSlots({
    required String startDate,
    required String endDate,
    String? facultyId,
    String? skillId,
  }) async {
    await ensureOnline();
    return _remote.freeSlots(startDate: startDate, endDate: endDate, facultyId: facultyId, skillId: skillId);
  }

  Future<List<FacultySuggestion>> suggestFaculty(SuggestFacultyQuery query) async {
    await ensureOnline();
    return _remote.suggestFaculty(query);
  }
}

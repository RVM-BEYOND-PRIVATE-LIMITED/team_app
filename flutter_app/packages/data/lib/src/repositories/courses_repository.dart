import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/courses_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff course catalog (Scheduler). Connectivity-guarded pass-throughs over the
/// data source — list + per-id detail (with books) + delete, plus the
/// create/update writes (whose mobile forms are deferred pending a books picker).
class CoursesRepository with ConnectivityGuard {
  CoursesRepository({required CoursesRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final CoursesRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<Course>> list() async {
    await ensureOnline();
    return _remote.list();
  }

  Future<Course> byId(String id) async {
    await ensureOnline();
    return _remote.byId(id);
  }

  Future<Course> create(CourseDraft draft) async {
    await ensureOnline();
    return _remote.create(draft);
  }

  Future<Course> update(String id, CourseDraft draft) async {
    await ensureOnline();
    return _remote.update(id, draft);
  }

  Future<void> delete(String id) async {
    await ensureOnline();
    return _remote.delete(id);
  }
}

import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/scheduler_remote_data_source.dart';
import 'connectivity_guard.dart';

class SchedulerRepository with ConnectivityGuard {
  SchedulerRepository({required SchedulerRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final SchedulerRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<AnnouncementItem>> announcements() async {
    await ensureOnline();
    return _remote.announcements();
  }

  Future<List<BatchSummary>> studentBatches(String studentId) async {
    await ensureOnline();
    return _remote.studentBatches(studentId);
  }
}

import 'package:core_network/core_network.dart';

import '../connectivity_guard.dart';
import '../datasources/priority_tasks_remote_data_source.dart';
import '../../domain/models.dart';

/// Priority-task inbox.
class PriorityTasksRepository with ConnectivityGuard {
  PriorityTasksRepository({required PriorityTasksRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final PriorityTasksRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<PriorityInbox> inbox() async {
    await ensureOnline();
    return _remote.inbox();
  }

  Future<PriorityTask> update(String id, {String? status, String? progressNote}) async {
    await ensureOnline();
    return _remote.update(id, status: status, progressNote: progressNote);
  }

  Future<PriorityTask> cancel(String id, String reason) async {
    await ensureOnline();
    return _remote.cancel(id, reason);
  }

  Future<void> acknowledge(String id) async {
    await ensureOnline();
    return _remote.acknowledge(id);
  }
}

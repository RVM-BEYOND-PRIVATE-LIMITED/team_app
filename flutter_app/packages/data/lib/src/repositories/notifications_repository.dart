import 'package:core_network/core_network.dart';

import '../datasources/notifications_remote_data_source.dart';
import 'connectivity_guard.dart';

class NotificationsRepository with ConnectivityGuard {
  NotificationsRepository({required NotificationsRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final NotificationsRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<int> unreadCount() async {
    await ensureOnline();
    return _remote.unreadCount();
  }
}

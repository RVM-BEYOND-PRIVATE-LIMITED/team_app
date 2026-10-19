import 'package:core_network/core_network.dart';

import '../connectivity_guard.dart';
import '../datasources/announcements_remote_data_source.dart';
import '../../domain/models.dart';

/// Branch announcements for Home.
class AnnouncementsRepository with ConnectivityGuard {
  AnnouncementsRepository({required AnnouncementsRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final AnnouncementsRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<TeamAnnouncement>> list() async {
    await ensureOnline();
    return _remote.list();
  }
}

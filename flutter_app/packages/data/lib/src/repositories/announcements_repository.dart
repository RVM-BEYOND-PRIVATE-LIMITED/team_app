import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/announcements_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff announcements console (Scheduler). Connectivity-guarded pass-throughs
/// over the data source — the branch-scoped list plus the compose + delete
/// writes.
class AnnouncementsRepository with ConnectivityGuard {
  AnnouncementsRepository({required AnnouncementsRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final AnnouncementsRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<AnnouncementItem>> list({String? locationId}) async {
    await ensureOnline();
    return _remote.list(locationId: locationId);
  }

  Future<AnnouncementItem> create(AnnouncementDraft draft) async {
    await ensureOnline();
    return _remote.create(draft);
  }

  Future<void> delete(String id) async {
    await ensureOnline();
    return _remote.delete(id);
  }
}

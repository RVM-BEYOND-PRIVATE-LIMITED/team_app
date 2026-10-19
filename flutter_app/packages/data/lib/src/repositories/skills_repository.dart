import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/skills_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff skill catalog (Scheduler). Connectivity-guarded pass-throughs over the
/// data source — the branch-scoped list plus the create/update/delete writes.
class SkillsRepository with ConnectivityGuard {
  SkillsRepository({required SkillsRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final SkillsRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<Skill>> list({String? locationId}) async {
    await ensureOnline();
    return _remote.list(locationId: locationId);
  }

  Future<Skill> create(SkillDraft draft) async {
    await ensureOnline();
    return _remote.create(draft);
  }

  Future<Skill> update(String id, SkillDraft draft) async {
    await ensureOnline();
    return _remote.update(id, draft);
  }

  Future<void> delete(String id) async {
    await ensureOnline();
    return _remote.delete(id);
  }
}

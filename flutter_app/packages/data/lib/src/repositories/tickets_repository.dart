import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/tickets_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff support-ticket console (Scheduler). Connectivity-guarded pass-throughs
/// over the data source — the paginated list, per-ticket detail + chat reads,
/// the assignable-admins / categories lookups, and the triage writes
/// (status/priority/assignee, reopen, delete, chat reply).
class TicketsRepository with ConnectivityGuard {
  TicketsRepository({required TicketsRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final TicketsRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<TicketsPage> list({
    String? status,
    String? category,
    String? search,
    String? locationId,
    String? from,
    String? to,
    int page = 1,
    int limit = 15,
  }) async {
    await ensureOnline();
    return _remote.list(
      status: status,
      category: category,
      search: search,
      locationId: locationId,
      from: from,
      to: to,
      page: page,
      limit: limit,
    );
  }

  Future<StaffTicket> detail(String id) async {
    await ensureOnline();
    return _remote.detail(id);
  }

  Future<StaffTicket> create(TicketDraft draft) async {
    await ensureOnline();
    return _remote.create(draft);
  }

  Future<List<TicketMessage>> chat(String ticketId) async {
    await ensureOnline();
    return _remote.chat(ticketId);
  }

  Future<List<NamedRef>> admins({String? locationId}) async {
    await ensureOnline();
    return _remote.admins(locationId: locationId);
  }

  Future<List<String>> categories() async {
    await ensureOnline();
    return _remote.categories();
  }

  Future<void> update(String id, TicketUpdate update) async {
    await ensureOnline();
    return _remote.update(id, update);
  }

  Future<void> reopen(String id) async {
    await ensureOnline();
    return _remote.reopen(id);
  }

  Future<void> delete(String id) async {
    await ensureOnline();
    return _remote.delete(id);
  }

  Future<void> reply({required String ticketId, required String message}) async {
    await ensureOnline();
    return _remote.reply(ticketId: ticketId, message: message);
  }
}

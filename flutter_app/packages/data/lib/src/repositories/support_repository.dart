import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/support_remote_data_source.dart';
import 'connectivity_guard.dart';

class SupportRepository with ConnectivityGuard {
  SupportRepository({required SupportRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final SupportRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<SupportTicket>> tickets() async {
    await ensureOnline();
    return _remote.tickets();
  }

  Future<SupportTicket> create({required String subject, required String message}) async {
    await ensureOnline();
    return _remote.create(subject: subject, message: message);
  }

  Future<TicketDetail> ticket(String id) async {
    await ensureOnline();
    return _remote.ticket(id);
  }

  Future<TicketReply> reply(String id, String message) async {
    await ensureOnline();
    return _remote.reply(id, message);
  }
}

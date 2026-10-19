import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/chat_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Candidate ↔ admin support chat (JobPortal).
class ChatRepository with ConnectivityGuard {
  ChatRepository({required ChatRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final ChatRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<ChatThread> thread() async {
    await ensureOnline();
    return _remote.thread();
  }

  Future<ChatMessage> send(String content) async {
    await ensureOnline();
    return _remote.send(content);
  }
}

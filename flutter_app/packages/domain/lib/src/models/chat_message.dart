/// One message in the candidate ↔ admin support chat
/// (GET/POST /candidates/chat[/messages]).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.content,
    required this.fromCandidate,
    this.isRead = false,
    this.createdAt,
  });

  final String id;
  final String content;

  /// True when the candidate sent it (`sender_type == 'candidate'`); false for
  /// admin replies — drives which side the bubble sits on.
  final bool fromCandidate;
  final bool isRead;
  final DateTime? createdAt;
}

/// The candidate's single support conversation with its messages.
class ChatThread {
  const ChatThread({this.conversationId, this.messages = const []});

  final String? conversationId;
  final List<ChatMessage> messages;
}

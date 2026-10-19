/// Candidate support tickets.
enum TicketStatus { open, replied, resolved, closed, unknown }

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String subject;
  final TicketStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class TicketReply {
  const TicketReply({
    required this.id,
    required this.message,
    this.senderRole,
    this.createdAt,
  });

  final String id;
  final String message;

  /// e.g. 'candidate' | 'admin' — drives which side the bubble sits.
  final String? senderRole;
  final DateTime? createdAt;

  bool get fromCandidate => (senderRole ?? '').toLowerCase() == 'candidate';
}

class TicketDetail {
  const TicketDetail({
    required this.id,
    required this.subject,
    required this.status,
    this.message,
    this.createdAt,
    this.updatedAt,
    this.replies = const [],
  });

  final String id;
  final String subject;
  final TicketStatus status;
  final String? message;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<TicketReply> replies;
}

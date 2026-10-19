import 'staff_substitution.dart' show NamedRef;

/// Scheduler support-ticket domain — the staff-side console over the `tickets`
/// table. Students raise tickets; staff triage them (status / priority /
/// assignee), reply in a chat thread, reopen, and delete. Branch-scoped;
/// super-admin sees every city.

/// A support ticket as the staff console sees it (GET /tickets item and
/// GET /tickets/:id share this shape; the list adds [studentTicketCount]).
class StaffTicket {
  const StaffTicket({
    required this.id,
    required this.title,
    this.description,
    this.status = 'Open',
    this.priority = 'Medium',
    this.category,
    this.createdAt,
    this.updatedAt,
    this.student,
    this.assignee,
    this.assigneeId,
    this.studentTicketCount = 0,
  });

  final String id;
  final String title;
  final String? description;

  /// Open | In Progress | Resolved.
  final String status;

  /// Low | Medium | High.
  final String priority;
  final String? category;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The student who raised the ticket ({id, name}).
  final NamedRef? student;

  /// The admin handling it ({id, username → name}); null when unassigned.
  final NamedRef? assignee;
  final String? assigneeId;

  /// How many tickets this student has raised in total (list view only).
  final int studentTicketCount;

  bool get isResolved => status == 'Resolved';
  bool get isAssigned => assigneeId != null && assigneeId!.isNotEmpty;
}

/// One page of GET /tickets → `{items, total, counts, page, limit}`.
class TicketsPage {
  const TicketsPage({
    required this.items,
    required this.total,
    required this.counts,
    this.page = 1,
    this.limit = 15,
  });
  final List<StaffTicket> items;
  final int total;
  final TicketCounts counts;
  final int page;
  final int limit;
}

/// Status tallies for the filter chips (GET /tickets `counts`), computed by the
/// backend across the whole filtered set (not just the current page).
class TicketCounts {
  const TicketCounts({this.all = 0, this.open = 0, this.inProgress = 0, this.resolved = 0});
  final int all;
  final int open;
  final int inProgress;
  final int resolved;

  int forStatus(String s) => switch (s) {
        'Open' => open,
        'In Progress' => inProgress,
        'Resolved' => resolved,
        _ => all,
      };
}

/// One chat message on a ticket (GET /tickets/:id/chat item). Exactly one of
/// [user] / [student] is set, identifying the sender.
class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.message,
    this.createdAt,
    this.senderUserId,
    this.senderStudentId,
    this.user,
    this.student,
  });
  final String id;
  final String message;
  final DateTime? createdAt;
  final String? senderUserId;
  final String? senderStudentId;

  /// Staff sender ({id, username → name}).
  final NamedRef? user;

  /// Student sender ({id, name}).
  final NamedRef? student;

  /// A staff/admin reply (vs the student who raised the ticket).
  bool get isFromStaff => (senderUserId != null && senderUserId!.isNotEmpty) || user != null;
  String get senderName => user?.name ?? student?.name ?? (isFromStaff ? 'Staff' : 'Student');
}

/// PATCH /tickets/:id body — status / priority / assignee, each optional; only
/// the provided fields are sent so an untouched field is left unchanged.
class TicketUpdate {
  const TicketUpdate({this.status, this.priority, this.assigneeId});
  final String? status;
  final String? priority;
  final String? assigneeId;

  Map<String, dynamic> toJson() => {
        if (status != null) 'status': status,
        if (priority != null) 'priority': priority,
        if (assigneeId != null) 'assignee_id': assigneeId,
      };
}

/// POST /tickets create payload — staff raising a ticket on behalf of a student.
/// [studentId] is required (the backend derives the ticket's location from it).
class TicketDraft {
  const TicketDraft({
    required this.title,
    required this.description,
    required this.studentId,
    this.priority,
    this.category,
  });

  final String title;
  final String description;
  final String studentId;
  final String? priority;
  final String? category;

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'student_id': studentId,
        if (priority != null) 'priority': priority,
        if (category != null && category!.isNotEmpty) 'category': category,
      };
}

/// The ticket workflow states + priorities the backend accepts.
const kTicketStatuses = <String>['Open', 'In Progress', 'Resolved'];
const kTicketPriorities = <String>['Low', 'Medium', 'High'];

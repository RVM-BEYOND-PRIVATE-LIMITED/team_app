/// Scheduler follow-up task management (collections / retention) — the due-task
/// worklist with today/overdue/upcoming counts, the per-staff activity report,
/// per-admission log history, and the create-log payload. Distinct from the
/// batch-allotment follow-up (different route + shapes).

/// One row of the follow-up task list (from v_follow_up_task_list).
class FollowUpTask {
  const FollowUpTask({
    required this.admissionId,
    required this.studentName,
    this.studentPhone,
    this.admissionNumber,
    this.batchName,
    this.nextDueDate,
    this.totalDue,
    this.taskCount = 0,
    this.assignedTo,
    this.lastLogAt,
  });

  final String admissionId;
  final String studentName;
  final String? studentPhone;
  final String? admissionNumber;
  final String? batchName;
  final DateTime? nextDueDate;
  final num? totalDue;
  final int taskCount;
  final String? assignedTo;
  final DateTime? lastLogAt;

  bool get owesMoney => (totalDue ?? 0) > 0;
}

/// GET /follow-ups → `{tasks:[...], counts:{today,overdue,upcoming}}`.
class FollowUpTasksPage {
  const FollowUpTasksPage({
    required this.tasks,
    this.today = 0,
    this.overdue = 0,
    this.upcoming = 0,
  });

  final List<FollowUpTask> tasks;
  final int today;
  final int overdue;
  final int upcoming;
}

/// A single history log entry (from follow_up_details + staff_name).
class FollowUpLog {
  const FollowUpLog({
    required this.id,
    this.date,
    this.notes,
    this.type,
    this.leadType,
    this.nextFollowUpDate,
    this.staffName,
  });

  final String id;
  final DateTime? date;
  final String? notes;
  final String? type;
  final String? leadType;
  final DateTime? nextFollowUpDate;
  final String? staffName;
}

/// One log inside a staff report entry (carries the student it was about).
class StaffFollowUpLog {
  const StaffFollowUpLog({
    required this.id,
    this.date,
    this.notes,
    this.type,
    this.leadType,
    this.nextFollowUpDate,
    this.studentName,
    this.studentPhone,
    this.admissionNumber,
  });

  final String id;
  final DateTime? date;
  final String? notes;
  final String? type;
  final String? leadType;
  final DateTime? nextFollowUpDate;
  final String? studentName;
  final String? studentPhone;
  final String? admissionNumber;
}

/// One staff member's follow-up activity in the report.
class StaffFollowUpEntry {
  const StaffFollowUpEntry({required this.staffName, required this.count, this.logs = const []});
  final String staffName;
  final int count;
  final List<StaffFollowUpLog> logs;
}

/// GET /follow-ups/staff-report → `{report:[...], total, startDate, endDate}`.
class StaffFollowUpReport {
  const StaffFollowUpReport({required this.entries, this.total = 0});
  final List<StaffFollowUpEntry> entries;
  final int total;
}

/// POST /follow-ups — the create-log payload.
class FollowUpLogDraft {
  const FollowUpLogDraft({
    required this.admissionId,
    required this.notes,
    this.type,
    this.leadType,
    this.nextFollowUpDate,
  });

  final String admissionId;
  final String notes;
  final String? type;
  final String? leadType;
  final DateTime? nextFollowUpDate;

  Map<String, dynamic> toJson() => {
        'admission_id': admissionId,
        'notes': notes,
        if (type != null) 'type': type,
        if (leadType != null) 'lead_type': leadType,
        if (nextFollowUpDate != null)
          'next_follow_up_date':
              '${nextFollowUpDate!.year.toString().padLeft(4, '0')}-${nextFollowUpDate!.month.toString().padLeft(2, '0')}-${nextFollowUpDate!.day.toString().padLeft(2, '0')}',
      };
}

/// The follow-up log types the create form offers.
const kFollowUpTypes = <String>['Call', 'Message', 'Visit', 'Email'];

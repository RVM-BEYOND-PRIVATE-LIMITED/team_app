/// Scheduler batch-allotment domain — the allotment worklist (admitted students
/// being placed into batches), their follow-up + remark history, and the
/// red-flag (at-risk) tracking.

/// One row of the allotment worklist.
class AllotmentRow {
  const AllotmentRow({
    required this.admissionId,
    required this.studentName,
    this.admissionNumber,
    this.phoneNumber,
    this.courseName,
    this.admissionDate,
    this.batchNames = const [],
    this.joined = false,
    this.joiningDate,
    this.remarks,
    this.redFlag = false,
    this.redFlagReason,
    this.totalDateChanges = 0,
    this.remarksCount = 0,
    this.followUpCount = 0,
  });

  final String admissionId;
  final String studentName;
  final String? admissionNumber;
  final String? phoneNumber;
  final String? courseName;
  final DateTime? admissionDate;
  final List<String> batchNames;
  final bool joined;
  final DateTime? joiningDate;
  final String? remarks;
  final bool redFlag;

  /// 'date_changes' | 'remarks' — why the student was flagged.
  final String? redFlagReason;
  final int totalDateChanges;
  final int remarksCount;
  final int followUpCount;

  bool get allotted => batchNames.isNotEmpty;
}

/// A single follow-up log entry.
class FollowUp {
  const FollowUp({
    required this.id,
    this.notes,
    this.status,
    this.type,
    this.followUpDate,
    this.nextFollowUpDate,
    this.createdAt,
    this.byUser,
  });

  final String id;
  final String? notes;
  final String? status;
  final String? type;
  final DateTime? followUpDate;
  final DateTime? nextFollowUpDate;
  final DateTime? createdAt;
  final String? byUser;
}

/// Follow-up history for one admission.
class FollowUpHistory {
  const FollowUpHistory({required this.studentName, required this.totalCount, this.followUps = const []});
  final String studentName;
  final int totalCount;
  final List<FollowUp> followUps;
}

/// One admission_remarks entry.
class AdmissionRemark {
  const AdmissionRemark({this.text, this.createdAt, this.createdBy});
  final String? text;
  final DateTime? createdAt;
  final String? createdBy;
}

/// A red-flagged (at-risk, not-yet-joined) student.
class RedFlagStudent {
  const RedFlagStudent({
    required this.admissionId,
    required this.studentName,
    this.admissionNumber,
    this.phoneNumber,
    this.redFlagReason,
    this.totalDateChanges = 0,
    this.remarksCount = 0,
  });

  final String admissionId;
  final String studentName;
  final String? admissionNumber;
  final String? phoneNumber;
  final String? redFlagReason;
  final int totalDateChanges;
  final int remarksCount;
}

/// GET /batch-allotment/red-flag-summary.
class RedFlagSummary {
  const RedFlagSummary({required this.totalRedFlagged, this.students = const []});
  final int totalRedFlagged;
  final List<RedFlagStudent> students;
}

// ── Write payloads ───────────────────────────────────────────────────────────

/// PUT /batch-allotment/:admissionId.
class AllotmentUpdate {
  const AllotmentUpdate({required this.joined, this.joiningDate, this.remarks});
  final bool joined;
  final DateTime? joiningDate;
  final String? remarks;

  Map<String, dynamic> toJson() => {
        'joined': joined,
        if (joiningDate != null)
          'joining_date':
              '${joiningDate!.year.toString().padLeft(4, '0')}-${joiningDate!.month.toString().padLeft(2, '0')}-${joiningDate!.day.toString().padLeft(2, '0')}',
        if (remarks != null) 'remarks': remarks,
      };
}

/// POST /batch-allotment/follow-ups/:admissionId.
class FollowUpDraft {
  const FollowUpDraft({required this.notes, this.status, this.nextFollowUpDate});
  final String notes;
  final String? status;
  final DateTime? nextFollowUpDate;

  Map<String, dynamic> toJson() => {
        'notes': notes,
        if (status != null) 'status': status,
        if (nextFollowUpDate != null)
          'next_follow_up_date':
              '${nextFollowUpDate!.year.toString().padLeft(4, '0')}-${nextFollowUpDate!.month.toString().padLeft(2, '0')}-${nextFollowUpDate!.day.toString().padLeft(2, '0')}',
      };
}

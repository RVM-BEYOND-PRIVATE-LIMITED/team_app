/// Scheduler student master record as the staff console sees it — the raw
/// `students` row enriched with the follow-up view (dynamic remark + true
/// balance) and the risk/hold flags the console surfaces.
class StaffStudent {
  const StaffStudent({
    required this.id,
    required this.name,
    this.admissionNumber,
    this.phoneNumber,
    this.remarks,
    this.locationId,
    this.totalDue,
    this.isOnHold = false,
    this.holdCategory,
    this.holdRemarks,
    this.isDefaulter = false,
    this.defaulterReason,
    this.isBanned = false,
    this.isSuspended = false,
    this.suspendedUntil,
    this.nextTaskDueDate,
    this.hasFollowupData = false,
  });

  final String id;
  final String name;
  final String? admissionNumber;
  final String? phoneNumber;

  /// Backend-computed display remark (due date / FULL PAID / manual remark).
  final String? remarks;
  final int? locationId;

  /// True balance from the follow-up view (0 = confirmed paid).
  final num? totalDue;
  final bool isOnHold;
  final String? holdCategory;
  final String? holdRemarks;
  final bool isDefaulter;
  final String? defaulterReason;
  final bool isBanned;
  final bool isSuspended;
  final DateTime? suspendedUntil;
  final DateTime? nextTaskDueDate;
  final bool hasFollowupData;

  bool get owesMoney => (totalDue ?? 0) > 0;

  /// The backend refuses to mark a student defaulter without an admission no.
  bool get hasAdmissionNumber =>
      admissionNumber != null && admissionNumber!.trim().isNotEmpty && admissionNumber != 'N/A';
}

/// One page of the paginated student list (GET /students → `{students,count}`).
class StudentsPage {
  const StudentsPage({required this.students, required this.count});
  final List<StaffStudent> students;

  /// Total matching the filter across all pages.
  final int count;
}

/// GET /students/:id/defaulter → `{is_defaulter, reason, has_admission_no}`.
class DefaulterStatus {
  const DefaulterStatus({required this.isDefaulter, this.reason, this.hasAdmissionNo = false});
  final bool isDefaulter;
  final String? reason;
  final bool hasAdmissionNo;
}

/// Create/update payload for a student (POST/PUT /students) — the exact
/// snake_case body the controller reads.
class StudentDraft {
  const StudentDraft({
    required this.name,
    this.admissionNumber,
    this.phoneNumber,
    this.remarks,
  });

  final String name;
  final String? admissionNumber;
  final String? phoneNumber;
  final String? remarks;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (admissionNumber != null) 'admission_number': admissionNumber,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (remarks != null) 'remarks': remarks,
      };
}

/// The allowed hold categories (mirrors the controller's HOLD_CATEGORIES).
const kHoldCategories = <String>['Medical', 'Personal', 'Exams', 'Others'];

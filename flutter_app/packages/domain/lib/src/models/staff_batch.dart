import 'batch_summary.dart';

/// Scheduler batch as the staff console sees it — richer than the student
/// [BatchSummary]: nested faculty/skill names, enrolled vs joined counts,
/// substitution flag, and the ids/schedule the edit form needs.
class StaffBatch {
  const StaffBatch({
    required this.id,
    required this.name,
    required this.status,
    this.description,
    this.facultyId,
    this.facultyName,
    this.skillId,
    this.skillName,
    this.startDate,
    this.endDate,
    this.startTime,
    this.endTime,
    this.maxStudents,
    this.enrolledCount,
    this.joinedCount,
    this.isSubstituted = false,
    this.originalFacultyName,
    this.scheduleDayNames = const [],
  });

  final String id;
  final String name;
  final BatchStatus status;
  final String? description;
  final String? facultyId;
  final String? facultyName;
  final String? skillId;
  final String? skillName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? startTime;
  final String? endTime;
  final int? maxStudents;

  /// Total students linked to the batch (`students` count).
  final int? enrolledCount;

  /// Students who have officially joined (`joined_count`).
  final int? joinedCount;

  /// A substitute faculty is currently covering this batch.
  final bool isSubstituted;
  final String? originalFacultyName;

  /// Weekday names the batch runs (e.g. ["Monday","Wednesday"]) — the
  /// `days_of_week` column. This is the value the create/update API expects
  /// back (matched case-insensitively against faculty availability); distinct
  /// from the numeric `schedule` column the attendance reports read.
  final List<String> scheduleDayNames;

  /// Seats left, when both counts are known.
  int? get seatsLeft =>
      (maxStudents != null && enrolledCount != null) ? (maxStudents! - enrolledCount!) : null;
}

/// A student row on a batch's roster (GET /batches/:id/students) — carries the
/// financial + risk flags the staff console highlights.
class BatchStudent {
  const BatchStudent({
    required this.id,
    required this.name,
    this.admissionNumber,
    this.phoneNumber,
    this.enrolledCourses,
    this.activeBatchesCount,
    this.remarks,
    this.totalDue,
    this.isDefaulter = false,
    this.isBanned = false,
    this.isSuspended = false,
    this.isOnHold = false,
    this.suspendedUntil,
    this.nextFollowUp,
    this.statusLabel,
  });

  final String id;
  final String name;
  final String? admissionNumber;
  final String? phoneNumber;
  final String? enrolledCourses;
  final int? activeBatchesCount;
  final String? remarks;
  final num? totalDue;
  final bool isDefaulter;
  final bool isBanned;
  final bool isSuspended;
  final bool isOnHold;
  final DateTime? suspendedUntil;
  final DateTime? nextFollowUp;

  /// "Admitted" / "Trial/Pending".
  final String? statusLabel;

  bool get owesMoney => (totalDue ?? 0) > 0;
}

/// GET /batches/active-students-count → the batches-tab header KPI.
class ActiveStudentsCount {
  const ActiveStudentsCount({required this.totalActiveStudents, required this.activeBatchesCount});
  final int totalActiveStudents;
  final int activeBatchesCount;
}

/// The batches landing in one shot: the list + the header KPI.
class BatchesOverview {
  const BatchesOverview({required this.batches, this.activeCount});
  final List<StaffBatch> batches;
  final ActiveStudentsCount? activeCount;
}

/// Create/update payload for a batch (POST/PUT /batches). Maps to the exact
/// camelCase body the controller reads.
class BatchDraft {
  const BatchDraft({
    required this.name,
    this.description,
    this.startDate,
    this.endDate,
    this.startTime,
    this.endTime,
    this.facultyId,
    this.skillId,
    this.maxStudents,
    this.studentIds = const [],
    this.daysOfWeek = const [],
    this.status,
  });

  /// Full ordered week, Sunday-first — day-name options for the schedule picker.
  static const weekDays = <String>[
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];

  final String name;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? startTime;
  final String? endTime;
  final String? facultyId;
  final String? skillId;
  final int? maxStudents;

  /// The FULL enrolment on update: the controller deletes every batch_students
  /// link and re-inserts from this list, so an update that omits it WIPES the
  /// roster. Always pass the current roster's student ids when editing.
  final List<String> studentIds;

  /// Day-NAME strings ("Monday" …) — the API matches these case-insensitively
  /// against faculty availability. NOT weekday numbers.
  final List<String> daysOfWeek;
  final String? status;

  static String? _ymd(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (startDate != null) 'startDate': _ymd(startDate),
        if (endDate != null) 'endDate': _ymd(endDate),
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        if (facultyId != null) 'facultyId': facultyId,
        if (skillId != null) 'skillId': skillId,
        if (maxStudents != null) 'maxStudents': maxStudents,
        if (studentIds.isNotEmpty) 'studentIds': studentIds,
        // Always sent (even empty): the controller iterates daysOfWeek for the
        // faculty-availability check and throws a 500 on `undefined`.
        'daysOfWeek': daysOfWeek,
        if (status != null) 'status': status,
      };
}

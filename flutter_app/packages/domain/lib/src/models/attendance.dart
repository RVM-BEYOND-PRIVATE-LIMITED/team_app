/// Scheduler attendance domain models — the daily roster + mark inputs, the
/// pending-absent-remarks queue, per-student history, and the several report
/// shapes. Grouped in one file because they're only ever used together by the
/// staff attendance feature.

/// One student row on the daily roster / mark screen.
class AttendanceEntry {
  const AttendanceEntry({
    required this.studentId,
    required this.studentName,
    required this.isPresent,
    this.admissionNumber,
    this.phoneNumber,
    this.isEligible = true,
    this.isOnHold = false,
    this.notYetJoined = false,
    this.isPlaceholder = false,
    this.absentReason,
    this.followUpComment,
  });

  final String studentId;
  final String studentName;
  final bool isPresent;
  final String? admissionNumber;
  final String? phoneNumber;

  /// Counts toward reports on this date (joined + not on hold). Not-eligible
  /// rows are still shown so faculty sees the whole class, just greyed out.
  final bool isEligible;
  final bool isOnHold;

  /// Batch link exists but the student hasn't officially joined yet — visible
  /// but not report-counted. Faculty may still mark them.
  final bool notYetJoined;

  /// No saved record yet for this date — a synthesised absent placeholder.
  final bool isPlaceholder;
  final String? absentReason;
  final String? followUpComment;

  /// Faculty may toggle everyone except not-yet-joined rows.
  bool get isMarkable => !notYetJoined;

  AttendanceEntry copyWith({bool? isPresent}) => AttendanceEntry(
        studentId: studentId,
        studentName: studentName,
        isPresent: isPresent ?? this.isPresent,
        admissionNumber: admissionNumber,
        phoneNumber: phoneNumber,
        isEligible: isEligible,
        isOnHold: isOnHold,
        notYetJoined: notYetJoined,
        isPlaceholder: isPlaceholder,
        absentReason: absentReason,
        followUpComment: followUpComment,
      );
}

/// A single historical session for a student (last-N dots + full log).
class AttendanceHistoryEntry {
  const AttendanceHistoryEntry({
    required this.date,
    required this.isPresent,
    this.absentReason,
    this.followUpComment,
    this.remarksUpdatedBy,
  });

  final DateTime date;
  final bool isPresent;
  final String? absentReason;
  final String? followUpComment;
  final String? remarksUpdatedBy;
}

/// An absent student whose remark (reason) is still missing — the actionable
/// unit of the "pending remarks" queue.
class PendingRemark {
  const PendingRemark({
    required this.attendanceId,
    required this.studentId,
    required this.studentName,
    this.date,
    this.admissionNumber,
    this.phoneNumber,
    this.absentReason,
    this.followUpComment,
    this.attendancePercentage,
    this.batchId,
    this.batchName,
  });

  final String attendanceId;
  final String studentId;
  final String studentName;
  final DateTime? date;
  final String? admissionNumber;
  final String? phoneNumber;
  final String? absentReason;
  final String? followUpComment;
  final int? attendancePercentage;
  final String? batchId;
  final String? batchName;

  bool get hasRemark => (absentReason ?? '').trim().isNotEmpty;
}

/// Pending remarks grouped by batch (powers the "Pending Remarks" list).
class PendingRemarksGroup {
  const PendingRemarksGroup({
    required this.batchId,
    required this.batchName,
    required this.pendingCount,
    required this.students,
    this.locationId,
    this.startTime,
  });

  final String batchId;
  final String batchName;
  final int pendingCount;
  final List<PendingRemark> students;
  final int? locationId;
  final String? startTime;
}

/// The attendance landing snapshot: today's overall % + the pending queue.
class AttendanceToday {
  const AttendanceToday({required this.groups, this.overallPercentage});

  final List<PendingRemarksGroup> groups;

  /// Lightweight dashboard KPI — null when no batch runs today.
  final double? overallPercentage;

  int get totalPending => groups.fold(0, (s, g) => s + g.pendingCount);
}

/// Everything the mark screen needs for a batch+date in one shot.
class MarkSheet {
  const MarkSheet({
    required this.entries,
    this.historyByStudent = const {},
    this.pendingRemarks = const [],
  });

  final List<AttendanceEntry> entries;
  final Map<String, List<AttendanceHistoryEntry>> historyByStudent;
  final List<PendingRemark> pendingRemarks;
}

// ── Reports ──────────────────────────────────────────────────────────────────

/// Per-location rollup inside the overall report.
class LocationAttendance {
  const LocationAttendance({
    required this.totalExpected,
    required this.totalPresent,
    this.locationId,
    this.percentage,
  });

  final int? locationId;
  final int totalExpected;
  final int totalPresent;
  final double? percentage;
}

/// Org-wide attendance over a date range, scoped to the caller's branch (or all
/// locations for super-admin).
class OverallAttendanceReport {
  const OverallAttendanceReport({
    required this.overallPercentage,
    required this.totalExpected,
    required this.totalPresent,
    required this.locations,
  });

  final double overallPercentage;
  final int totalExpected;
  final int totalPresent;
  final List<LocationAttendance> locations;
}

/// One batch line inside a faculty / compliance report.
class FacultyBatchLine {
  const FacultyBatchLine({
    required this.batchId,
    required this.batchName,
    this.status,
    this.studentCount,
    this.expectedSessions,
    this.markedSessions,
    this.percentage,
    this.missingDates = const [],
    this.isComplete = true,
  });

  final String batchId;
  final String batchName;
  final String? status;
  final int? studentCount;
  final int? expectedSessions;
  final int? markedSessions;

  /// null = no eligible students in range — render "—", not 0%.
  final double? percentage;
  final List<String> missingDates;
  final bool isComplete;
}

/// A batch whose faculty owes attendance logs.
class MissingLog {
  const MissingLog({required this.batchName, required this.count});
  final String batchName;
  final int count;
}

/// Detailed audit for one faculty over a date range.
class FacultyAttendanceReport {
  const FacultyAttendanceReport({
    required this.facultyId,
    required this.facultyName,
    this.percentage,
    this.batches = const [],
    this.missingLogs = const [],
  });

  final String facultyId;
  final String facultyName;
  final double? percentage;
  final List<FacultyBatchLine> batches;
  final List<MissingLog> missingLogs;
}

/// One faculty inside the org compliance audit.
class ComplianceFacultyLine {
  const ComplianceFacultyLine({
    required this.facultyId,
    required this.facultyName,
    this.locationId,
    this.percentage,
    this.batches = const [],
    this.missingLogs = const [],
  });

  final String facultyId;
  final String facultyName;
  final int? locationId;
  final double? percentage;
  final List<FacultyBatchLine> batches;
  final List<MissingLog> missingLogs;
}

/// Full per-faculty compliance audit with batch breakdown.
class ComplianceReport {
  const ComplianceReport({required this.overallPercentage, required this.faculties});
  final double overallPercentage;
  final List<ComplianceFacultyLine> faculties;
}

/// A student row in the batch attendance report (over a date range).
class BatchReportStudent {
  const BatchReportStudent({
    required this.id,
    required this.name,
    this.admissionNumber,
    this.phoneNumber,
    this.remarks,
    this.totalDue,
    this.isDefaulter = false,
    this.isBanned = false,
    this.isSuspended = false,
  });

  final String id;
  final String name;
  final String? admissionNumber;
  final String? phoneNumber;
  final String? remarks;
  final num? totalDue;
  final bool isDefaulter;
  final bool isBanned;
  final bool isSuspended;
}

/// Student-by-student batch report + session compliance counts. The heavy
/// per-date grid is intentionally dropped — mobile shows the roster + counts.
class BatchAttendanceReport {
  const BatchAttendanceReport({
    required this.students,
    required this.expectedDays,
    required this.markedDays,
  });

  final List<BatchReportStudent> students;
  final int expectedDays;
  final int markedDays;
}

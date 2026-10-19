/// Scheduler persistent alert (currently only "absent remark missing") — a
/// per-student, per-date flag that a faculty/admin must resolve by filling the
/// missing attendance remark. Branch-scoped; shown as a worklist.
class PendingAlert {
  const PendingAlert({
    required this.id,
    this.alertType,
    this.date,
    this.dateRaw,
    this.batchId,
    this.studentId,
    this.studentName,
    this.admissionNumber,
    this.batchName,
    this.escalated = false,
    this.createdAt,
  });

  final String id;
  final String? alertType;
  final DateTime? date;

  /// The raw `date` string as stored (used verbatim for bulk-resolve).
  final String? dateRaw;
  final String? batchId;
  final String? studentId;
  final String? studentName;
  final String? admissionNumber;
  final String? batchName;
  final bool escalated;
  final DateTime? createdAt;
}

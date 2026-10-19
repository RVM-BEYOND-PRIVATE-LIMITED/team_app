/// Scheduler admissions as the staff console sees them — the enriched list row,
/// the financial metrics header, the single-admission detail (with courses +
/// installment schedule), and the phone-lookup result used by intake.

/// Financial rollup returned alongside the admissions list.
class AdmissionMetrics {
  const AdmissionMetrics({
    this.totalAdmissions = 0,
    this.admissionsThisMonth = 0,
    this.totalCollected = 0,
    this.revenueCollectedThisMonth = 0,
    this.totalOutstanding = 0,
    this.overdueCount = 0,
  });

  final int totalAdmissions;
  final int admissionsThisMonth;
  final num totalCollected;
  final num revenueCollectedThisMonth;
  final num totalOutstanding;
  final int overdueCount;
}

/// One admission row (list + dropout registry share this shape).
class AdmissionRow {
  const AdmissionRow({
    required this.id,
    required this.studentName,
    this.admissionNumber,
    this.phoneNumber,
    this.status,
    this.undertakingStatus,
    this.approvalStatus,
    this.totalPaid,
    this.totalFees,
    this.effectiveRemaining,
    this.createdAt,
    this.nextTaskDueDate,
    this.isDropout = false,
    this.dropoutReason,
    this.dropoutAt,
  });

  final String id;
  final String studentName;
  final String? admissionNumber;
  final String? phoneNumber;
  final String? status;

  /// 'Completed' / 'Pending' — the undertaking (signed agreement) state.
  final String? undertakingStatus;
  final String? approvalStatus;
  final num? totalPaid;
  final num? totalFees;

  /// Installment-schedule remaining due (source of truth for balance).
  final num? effectiveRemaining;
  final DateTime? createdAt;
  final DateTime? nextTaskDueDate;
  final bool isDropout;
  final String? dropoutReason;
  final DateTime? dropoutAt;

  bool get undertakingDone => (undertakingStatus ?? '').toLowerCase() == 'completed';
  bool get owesMoney => (effectiveRemaining ?? 0) > 0;
}

/// The admissions list payload: metrics header + rows.
class AdmissionsPage {
  const AdmissionsPage({required this.metrics, required this.admissions});
  final AdmissionMetrics metrics;
  final List<AdmissionRow> admissions;
}

/// A course linked to an admission.
class AdmissionCourse {
  const AdmissionCourse({required this.id, required this.name});
  final String id;
  final String name;
}

/// One installment row from the payment schedule (v_installment_status).
class AdmissionInstallment {
  const AdmissionInstallment({
    this.label,
    this.amount,
    this.paidAmount,
    this.dueDate,
    this.status,
  });

  final String? label;
  final num? amount;
  final num? paidAmount;
  final DateTime? dueDate;
  final String? status;
}

/// A single admission with its courses + installment schedule.
class AdmissionDetail {
  const AdmissionDetail({
    required this.row,
    this.courses = const [],
    this.installments = const [],
  });

  final AdmissionRow row;
  final List<AdmissionCourse> courses;
  final List<AdmissionInstallment> installments;
}

/// GET /admissions/by-phone/:phone → whether a phone already has an admission.
class AdmissionPhoneCheck {
  const AdmissionPhoneCheck({required this.exists, this.admissionId, this.undertakingCompleted});

  /// true = an admission exists (mode ADMISSION); false = INTAKE (new).
  final bool exists;
  final String? admissionId;
  final bool? undertakingCompleted;
}

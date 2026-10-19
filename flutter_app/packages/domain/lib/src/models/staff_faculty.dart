/// Scheduler faculty (HR) domain — the faculty roster with skills + weekly
/// availability + leave/active status, plus the per-faculty student metrics.

/// A skill a faculty can teach.
class FacultySkill {
  const FacultySkill({required this.id, required this.name});
  final String id;
  final String name;
}

/// One weekly availability slot.
class FacultyAvailability {
  const FacultyAvailability({this.id, this.dayOfWeek, this.startTime, this.endTime});
  final String? id;
  final String? dayOfWeek;
  final String? startTime;
  final String? endTime;
}

/// A faculty member.
class Faculty {
  const Faculty({
    required this.id,
    required this.name,
    this.email,
    this.phoneNumber,
    this.employmentType,
    this.isActive = true,
    this.locationId,
    this.status,
    this.leaveStartDate,
    this.leaveEndDate,
    this.leaveReason,
    this.skills = const [],
    this.availability = const [],
    // Merged in from the metrics endpoints (not part of the base row).
    this.activeStudents,
    this.totalStudents,
  });

  final String id;
  final String name;
  final String? email;
  final String? phoneNumber;
  final String? employmentType;
  final bool isActive;
  final int? locationId;

  /// Backend-computed: Active / On Leave / Inactive.
  final String? status;
  final DateTime? leaveStartDate;
  final DateTime? leaveEndDate;
  final String? leaveReason;
  final List<FacultySkill> skills;
  final List<FacultyAvailability> availability;

  /// Currently-active (eligible) students across the faculty's active batches.
  final int? activeStudents;

  /// All-time distinct students taught.
  final int? totalStudents;

  bool get onLeave => leaveStartDate != null && leaveEndDate != null;

  Faculty withMetrics({int? active, int? total}) => Faculty(
        id: id,
        name: name,
        email: email,
        phoneNumber: phoneNumber,
        employmentType: employmentType,
        isActive: isActive,
        locationId: locationId,
        status: status,
        leaveStartDate: leaveStartDate,
        leaveEndDate: leaveEndDate,
        leaveReason: leaveReason,
        skills: skills,
        availability: availability,
        activeStudents: active ?? activeStudents,
        totalStudents: total ?? totalStudents,
      );
}

/// GET /faculty/total-students/:id → `{total_students, students:[ids]}`.
class FacultyTotalStudents {
  const FacultyTotalStudents({required this.total, this.studentIds = const []});
  final int total;
  final List<String> studentIds;
}

// ── Write payloads ───────────────────────────────────────────────────────────

/// PUT /faculty/:id. Omit [skillIds] (null) to PRESERVE the faculty's skills —
/// the controller only rebuilds faculty_skills when skillIds is provided.
class FacultyUpdate {
  const FacultyUpdate({
    this.name,
    this.phoneNumber,
    this.employmentType,
    this.isActive,
    this.leaveStartDate,
    this.leaveEndDate,
    this.leaveReason,
    this.skillIds,
  });

  final String? name;
  final String? phoneNumber;
  final String? employmentType;
  final bool? isActive;
  final DateTime? leaveStartDate;
  final DateTime? leaveEndDate;
  final String? leaveReason;
  final List<String>? skillIds;

  static String? _ymd(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (employmentType != null) 'employment_type': employmentType,
        if (isActive != null) 'is_active': isActive,
        // Send leave fields explicitly (including null) so clearing them
        // persists — the controller only clears a field it actually receives.
        'leave_start_date': _ymd(leaveStartDate),
        'leave_end_date': _ymd(leaveEndDate),
        'leave_reason': leaveReason,
        if (skillIds != null) 'skillIds': skillIds,
      };
}

/// POST /faculty — links an existing user as faculty. (Create form lands with
/// the users + skills modules; the payload is wired for when it does.)
class FacultyDraft {
  const FacultyDraft({
    required this.userId,
    this.email,
    this.phoneNumber,
    this.employmentType,
    this.skillIds = const [],
  });

  final String userId;
  final String? email;
  final String? phoneNumber;
  final String? employmentType;
  final List<String> skillIds;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        if (email != null) 'email': email,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (employmentType != null) 'employment_type': employmentType,
        if (skillIds.isNotEmpty) 'skillIds': skillIds,
      };
}

/// The employment types the edit form offers.
const kEmploymentTypes = <String>['Full-time', 'Part-time', 'Visiting', 'Contract'];

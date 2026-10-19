/// The signed-in candidate/student, trimmed for the app shell (Home header,
/// profile, and match scoring).
class CandidateProfile {
  const CandidateProfile({
    required this.id,
    this.fullName,
    this.phone,
    this.city,
    this.state,
    this.avatarUrl,
    this.resumeUrl,
    this.skills = const [],
    this.profileCompletionPct,
    this.jobDomain,
    this.jobRole,
    this.expectedSalaryMinLpa,
    this.expectedSalaryMaxLpa,
    this.preferredLocations = const [],
    this.isPremium = false,
  });

  final String id;
  final String? fullName;

  /// 10-digit Indian mobile — the cross-system key linking this JobPortal
  /// candidate to their Scheduler admission/student record.
  final String? phone;
  final String? city;
  final String? state;
  final String? avatarUrl;
  final String? resumeUrl;

  /// Merged technical skills + CAD software — the set match scoring uses.
  final List<String> skills;
  final int? profileCompletionPct;
  final String? jobDomain;
  final String? jobRole;
  final num? expectedSalaryMinLpa;
  final num? expectedSalaryMaxLpa;
  final List<String> preferredLocations;
  final bool isPremium;
}

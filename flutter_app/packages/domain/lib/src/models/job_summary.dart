/// JobPortal posting, trimmed for the browse/detail screens.
enum JobType { fullTime, partTime, contract, internship, unknown }

class JobSummary {
  const JobSummary({
    required this.id,
    required this.title,
    required this.jobType,
    this.companyId,
    this.companyName,
    this.location,
    this.salaryMinLpa,
    this.salaryMaxLpa,
    this.requiredSkills = const [],
    this.requiredDomain,
    this.openings,
    this.applicationDeadline,
    this.postedAt,
  });

  final String id;
  final String title;
  final JobType jobType;
  final String? companyId;
  final String? companyName;
  final String? location;
  final num? salaryMinLpa;
  final num? salaryMaxLpa;
  final List<String> requiredSkills;
  final String? requiredDomain;
  final int? openings;
  final DateTime? applicationDeadline;

  /// When the posting went live. Null until the backend exposes `created_at`
  /// on the browse payload — the feed card hides "posted" when absent.
  final DateTime? postedAt;
}

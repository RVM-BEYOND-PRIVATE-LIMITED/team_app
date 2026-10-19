import 'job_summary.dart';

/// Full job posting for the detail screen. Superset of [JobSummary] with the
/// fields only the detail view needs (description, experience, company meta).
class JobDetail {
  const JobDetail({
    required this.id,
    required this.title,
    required this.jobType,
    this.companyId,
    this.companyName,
    this.companyVerified = false,
    this.companySubtitle,
    this.location,
    this.salaryMinLpa,
    this.salaryMaxLpa,
    this.requiredSkills = const [],
    this.requiredDomain,
    this.requiredRole,
    this.openings,
    this.experienceMinMonths,
    this.experienceMaxMonths,
    this.description,
    this.applicationDeadline,
  });

  final String id;
  final String title;
  final JobType jobType;
  final String? companyId;
  final String? companyName;
  final bool companyVerified;

  /// e.g. "EV OEM · 900 staff · Verified" — assembled from industry + size.
  final String? companySubtitle;
  final String? location;
  final num? salaryMinLpa;
  final num? salaryMaxLpa;
  final List<String> requiredSkills;
  final String? requiredDomain;
  final String? requiredRole;
  final int? openings;
  final int? experienceMinMonths;
  final int? experienceMaxMonths;
  final String? description;
  final DateTime? applicationDeadline;
}

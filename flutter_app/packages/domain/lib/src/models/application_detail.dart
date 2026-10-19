import 'application_summary.dart';

/// Full application for the tracking detail screen (status timeline + withdraw).
class ApplicationDetail {
  const ApplicationDetail({
    required this.id,
    required this.status,
    required this.jobId,
    this.jobTitle,
    this.companyName,
    this.location,
    this.salaryMinLpa,
    this.salaryMaxLpa,
    this.coverNote,
    this.appliedAt,
    this.updatedAt,
  });

  final String id;
  final ApplicationStatus status;
  final String jobId;
  final String? jobTitle;
  final String? companyName;
  final String? location;
  final num? salaryMinLpa;
  final num? salaryMaxLpa;
  final String? coverNote;
  final DateTime? appliedAt;
  final DateTime? updatedAt;

  /// Backend allows withdrawal only while applied / pending / under review.
  bool get canWithdraw => switch (status) {
        ApplicationStatus.pending || ApplicationStatus.underReview => true,
        _ => false,
      };
}

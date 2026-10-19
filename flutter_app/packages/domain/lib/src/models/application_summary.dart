/// A candidate's job application, as the tracking screen shows it.
enum ApplicationStatus {
  pending,
  underReview,
  shortlisted,
  interviewScheduled,
  offerMade,
  hired,
  rejected,
  withdrawn,
  unknown,
}

class ApplicationSummary {
  const ApplicationSummary({
    required this.id,
    required this.jobId,
    required this.status,
    this.jobTitle,
    this.companyName,
    this.appliedAt,
  });

  final String id;
  final String jobId;
  final ApplicationStatus status;
  final String? jobTitle;
  final String? companyName;
  final DateTime? appliedAt;
}

/// Whether an application is still "live" (counts toward Home's active apps).
bool isActiveApplication(ApplicationStatus s) => switch (s) {
      ApplicationStatus.rejected ||
      ApplicationStatus.withdrawn ||
      ApplicationStatus.hired ||
      ApplicationStatus.unknown =>
        false,
      _ => true,
    };

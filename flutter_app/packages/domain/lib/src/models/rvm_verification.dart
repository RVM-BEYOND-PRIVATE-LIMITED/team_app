/// A candidate's RVM training-verification record
/// (GET/POST /candidates/rvm-verification). Whole feature is backend-flag-gated.
class RvmVerification {
  const RvmVerification({
    required this.id,
    required this.status,
    this.trainingStartDate,
    this.trainingEndDate,
    this.industry,
    this.jobDomain,
    this.jobRole,
    this.skills = const [],
    this.certificateFileName,
    this.submittedAt,
    this.reviewedAt,
    this.adminNotes,
    this.rejectionReason,
  });

  final String id;

  /// `pending_review` | `approved` | `rejected` (+ any future backend value).
  final String status;
  final String? trainingStartDate;
  final String? trainingEndDate;
  final String? industry;
  final String? jobDomain;
  final String? jobRole;
  final List<String> skills;
  final String? certificateFileName;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? adminNotes;
  final String? rejectionReason;

  bool get isPending => status == 'pending_review';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

/// GET response wrapper: whether the feature is enabled + the latest record.
class RvmVerificationStatus {
  const RvmVerificationStatus({this.featureEnabled = false, this.verification});

  final bool featureEnabled;
  final RvmVerification? verification;

  /// A candidate may submit only when the feature is on and they have no
  /// pending/approved record.
  bool get canSubmit =>
      featureEnabled && (verification == null || verification!.isRejected);
}

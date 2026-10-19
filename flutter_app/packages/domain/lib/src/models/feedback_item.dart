/// What the feedback is about (POST /feedback `feedback_type`).
enum FeedbackType { bug, suggestion, complaint, featureRequest, jobIssue, accountIssue, other }

extension FeedbackTypeX on FeedbackType {
  /// Human label for the type dropdown.
  String get label => switch (this) {
        FeedbackType.bug => 'Bug',
        FeedbackType.suggestion => 'Suggestion',
        FeedbackType.complaint => 'Complaint',
        FeedbackType.featureRequest => 'Feature request',
        FeedbackType.jobIssue => 'Job issue',
        FeedbackType.accountIssue => 'Account issue',
        FeedbackType.other => 'Other',
      };
}

/// One of the current user's own feedback submissions (GET /feedback).
class FeedbackItem {
  const FeedbackItem({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.status,
    this.createdAt,
  });

  final String id;
  final FeedbackType type;
  final String title;
  final String? description;

  /// Server-side lifecycle: new/reviewing/planned/in_progress/resolved/…
  final String? status;
  final DateTime? createdAt;
}

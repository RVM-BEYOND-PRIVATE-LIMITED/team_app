import 'job_summary.dart';

/// A bookmarked job. The backend keys the saved record by its OWN id
/// ([savedId]), which unsave (DELETE /candidates/saved-jobs/{savedId}) needs —
/// distinct from the job's id.
class SavedJob {
  const SavedJob({required this.savedId, required this.job});
  final String savedId;
  final JobSummary job;
}

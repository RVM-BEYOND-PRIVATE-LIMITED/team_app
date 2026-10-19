/// An institute / batch / placement announcement, as the Home carousel and
/// Announcements screen render it.
enum AnnouncementCategory { institute, batch, placement, unknown }

class AnnouncementItem {
  const AnnouncementItem({
    required this.id,
    required this.title,
    required this.category,
    this.body,
    this.batchId,
    this.batchName,
    this.createdAt,
  });

  final String id;
  final String title;
  final AnnouncementCategory category;
  final String? body;
  final String? batchId;

  /// Joined `batch:batches(name)` — set for batch-scoped announcements.
  final String? batchName;
  final DateTime? createdAt;

  /// True for a batch-specific announcement (vs an all-branch one).
  bool get isBatchScoped => category == AnnouncementCategory.batch;
}

/// The staff compose payload for POST /announcements. [scope] is 'all'
/// (whole branch) or 'batch'; [batchId] is required only when scope == 'batch'.
class AnnouncementDraft {
  const AnnouncementDraft({
    required this.title,
    required this.message,
    required this.scope,
    this.batchId,
  });

  final String title;
  final String message;
  final String scope;
  final String? batchId;

  Map<String, dynamic> toJson() => {
        'title': title,
        'message': message,
        'scope': scope,
        if (scope == 'batch') 'batch_id': batchId,
      };
}

/// The two announcement scopes the backend accepts.
const kAnnouncementScopeAll = 'all';
const kAnnouncementScopeBatch = 'batch';

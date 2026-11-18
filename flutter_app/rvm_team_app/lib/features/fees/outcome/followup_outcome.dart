/// How a fees follow-up call went (team_app #53, item 8).
///
/// Each [label] is the word the Scheduler already writes in
/// `follow_ups.status` (controllers/batchAllotmentController.js,
/// `FOLLOW_UP_STATUSES`), and the outcome Scheduler_Backend#176 adds to the
/// fees follow-up save.
enum FollowupOutcome {
  answered('Answered'),
  noAnswer('No Answer');

  const FollowupOutcome(this.label);

  /// The text shown on the form, the same word the Scheduler stores.
  final String label;
}

/// What the outcome form hands back on Save: the call's outcome, the remark,
/// the next follow-up day and the key for the save.
///
/// It is not sent anywhere yet. The save waits for Scheduler_Backend#176,
/// whose contract names the fields, so there is no JSON here. When it is
/// wired, [idempotencyKey] travels as
/// `Options(extra: {IdempotencyInterceptor.extraKey: idempotencyKey})`,
/// merged with `TeamModule.fees.requestOptions`.
class FollowupOutcomeDraft {
  const FollowupOutcomeDraft({
    required this.outcome,
    required this.remark,
    required this.idempotencyKey,
    this.nextDate,
  });

  final FollowupOutcome outcome;

  /// The remark as typed, trimmed. It may be empty: the Scheduler stores
  /// `notes || ''` today (controllers/followUpController.js).
  final String remark;

  /// The next follow-up day, a calendar date (only its year, month and day
  /// mean anything), or null for none. When set, it is after IST today
  /// (`validateNextFollowUpDate`).
  final DateTime? nextDate;

  /// One key for the sheet that made this draft, from
  /// `IdempotencyInterceptor.newKey()`: every Save of that sheet carries it.
  final String idempotencyKey;
}

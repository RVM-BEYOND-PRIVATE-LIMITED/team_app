/// The color state of one scorecard number (#55, item 6).
///
/// The server compares each number with its target, in the target's own
/// better direction, and sends `green`, `red` or `none` when there is no
/// target (Scheduler_Backend#177, item 11). The app never works a state out
/// itself: it only shows the one it is sent.
enum ScoreState {
  /// At or better than the target.
  green,

  /// Worse than the target.
  red,

  /// No target, so no color.
  none,
}

/// The server's `state` string as a [ScoreState]. Never throws: a missing,
/// misspelt, non-string or not-yet-known value is [ScoreState.none], so the
/// app can never show green or red that the server did not send.
ScoreState parseScoreState(Object? raw) {
  if (raw is! String) return ScoreState.none;
  return switch (raw.trim().toLowerCase()) {
    'green' => ScoreState.green,
    'red' => ScoreState.red,
    // 'none' (no target), and anything this build does not know.
    _ => ScoreState.none,
  };
}

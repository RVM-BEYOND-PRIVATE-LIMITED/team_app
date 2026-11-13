import 'package:flutter/material.dart';

import '../../widgets/team_kit.dart';
import 'score_state.dart';

/// A scorecard number's state as a pill (#55, item 6). Green and red show
/// their color with an icon and a word, so color is never the only signal.
/// `none` (no target) shows no color: the neutral pill, a dash and a word.
///
/// The words do not say above or below: the server has already applied each
/// target's better direction (for dropouts, fewer is better).
///
/// It shows a [ScoreState] and nothing else. A number the server sends with
/// `available: false` (Scheduler_Backend#177, item 7) can still have a
/// target, so do not show it here as `none` ("No target"): how such a number
/// shows is for the `ScoreNumber` model (#55, item 2) to decide.
///
/// Room: in the app's font the pill needs about 90 px at the default text
/// size and about 140 px at twice that (dense: about 78 px at the default).
/// With less it shrinks as a whole instead of overflowing, and its word
/// shrinks with it: in a 56 px column the word draws under 7 px at 1x and
/// under 9 px at 2x, smaller than its normal 10.5 px. Where a cell is that
/// tight, use [dense] or an icon with a screen-reader label instead. It only
/// shrinks when its parent limits its width: as a plain [Row] child (not in
/// a [Flexible]) or in a sideways scroll it keeps its full size.
class ScoreStateBadge extends StatelessWidget {
  const ScoreStateBadge({super.key, required this.state, this.dense = false});

  final ScoreState state;

  /// The smaller pill, for tight places such as one branch column on a small
  /// phone.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = switch (state) {
      ScoreState.green => (
          'On target',
          TeamPillTone.success,
          Icons.check_circle_rounded
        ),
      ScoreState.red => (
          'Off target',
          TeamPillTone.danger,
          Icons.error_outline_rounded
        ),
      ScoreState.none => (
          'No target',
          TeamPillTone.neutral,
          Icons.remove_rounded
        ),
    };
    // When a narrow column or a large text size leaves less room than the
    // pill needs, it scales down instead of overflowing. The word stays
    // whole but gets smaller (see "Room" above).
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: TeamPill(label: label, tone: tone, icon: icon, dense: dense),
    );
  }
}

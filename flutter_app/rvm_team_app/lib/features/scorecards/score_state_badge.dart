import 'package:flutter/material.dart';

import '../../widgets/team_kit.dart';
import 'score_state.dart';

/// A scorecard number's state as a pill (#55, item 6). Green and red show
/// their color with an icon and a word, so color is never the only signal.
/// `none` (no target) shows no color: the neutral pill, a dash and a word.
///
/// The words do not say above or below: the server has already applied each
/// target's better direction (for dropouts, fewer is better).
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
    // pill needs, it scales down instead of overflowing; the word stays whole.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: TeamPill(label: label, tone: tone, icon: icon, dense: dense),
    );
  }
}

import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

/// Why a screen cannot be used right now (team_app #50, item 12).
enum BlockedReason {
  /// The module is switched off for everyone.
  moduleOff(
    icon: Icons.toggle_off_outlined,
    title: 'Not switched on yet',
    message: 'This part of Team RVM is switched off for now.',
  ),

  /// The module is on only for the people in its pilot.
  pilotOnly(
    icon: Icons.science_outlined,
    title: 'In pilot',
    message: 'Only the people in the pilot can use this for now.',
  ),

  /// The module works only while the person is punched in.
  notPunchedIn(
    icon: Icons.fingerprint,
    title: 'Punch in first',
    message: 'Punch in for today to use this.',
  ),

  /// This build is older than the minimum version the server accepts.
  updateRequired(
    icon: Icons.system_update_alt,
    title: 'Update required',
    message: 'This version of Team RVM is no longer supported. '
        'Please update to continue.',
  );

  const BlockedReason({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;
}

/// The one blocked screen, whatever the reason (team_app #50, item 12):
/// an icon, a title, what to do, and at most one action. It fills the space
/// it is given and scrolls rather than overflow on a small phone or with large
/// text.
class BlockedState extends StatelessWidget {
  const BlockedState({
    super.key,
    required this.reason,
    this.message,
    this.actionLabel,
    this.actionIcon = Icons.refresh,
    this.onAction,
  });

  final BlockedReason reason;

  /// Replaces the reason's own message, e.g. to name the version to update to.
  final String? message;

  /// The action's label; no label, no action.
  final String? actionLabel;
  final IconData actionIcon;

  /// Null shows the action disabled, e.g. while a check is running.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final label = actionLabel;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(RvmSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(reason.icon, size: 48),
              const SizedBox(height: RvmSpacing.md),
              Text(reason.title,
                  textAlign: TextAlign.center, style: text.titleLarge),
              const SizedBox(height: RvmSpacing.sm),
              Text(
                message ?? reason.message,
                textAlign: TextAlign.center,
                style: text.bodyMedium,
              ),
              if (label != null) ...[
                const SizedBox(height: RvmSpacing.lg),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon),
                  label: Text(label),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

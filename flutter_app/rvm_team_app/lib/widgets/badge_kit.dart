import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../domain/ess_models.dart';

/// One icon per badge group, shared by the Wall's picker and the profile card so
/// a badge looks the same everywhere (KP, issue 24 follow-up).
IconData praiseBadgeIcon(String? forGroup) => switch (forGroup) {
      'teaching' => Icons.menu_book_outlined,
      'placement' => Icons.rocket_launch_outlined,
      'teamwork' => Icons.groups_outlined,
      'care' => Icons.favorite_outline,
      'effort' => Icons.bolt_outlined,
      'people' => Icons.diversity_3_outlined,
      'outreach' => Icons.campaign_outlined,
      'quality' => Icons.verified_outlined,
      _ => Icons.emoji_events_outlined,
    };

/// A gold ring and a small trophy count around an employee's avatar when they
/// have earned badges. With no badges the avatar is returned untouched.
class EarnedBadgeFrame extends StatelessWidget {
  const EarnedBadgeFrame({
    super.key,
    required this.child,
    required this.badgeCount,
  });

  final Widget child;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    if (badgeCount <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF5C451), RvmColors.teamSeed, Color(0xFFB86F36)],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: RvmColors.ivory,
            ),
            child: child,
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: RvmColors.teamSeed,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: RvmColors.ivory, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events_rounded,
                    size: 12, color: Colors.white),
                const SizedBox(width: 3),
                Text(
                  '$badgeCount',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The profile's earned-badge shelf: one chip per badge, with a repeat count.
class EarnedBadgesCard extends StatelessWidget {
  const EarnedBadgesCard({super.key, required this.badges});

  final List<EarnedBadge> badges;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events_outlined,
                    size: 20, color: RvmColors.teamSeed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Badges earned',
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text('${badges.length}',
                    style: text.labelLarge
                        ?.copyWith(color: RvmColors.subtle)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final badge in badges) _BadgeChip(badge: badge),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge});

  final EarnedBadge badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: RvmColors.cream,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: RvmColors.sand),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(praiseBadgeIcon(badge.forGroup),
              size: 16, color: RvmColors.teamSeed),
          const SizedBox(width: 6),
          Text(
            badge.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: RvmColors.ink,
                ),
          ),
          if (badge.count > 1) ...[
            const SizedBox(width: 5),
            Text(
              '×${badge.count}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: RvmColors.teamSeed,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

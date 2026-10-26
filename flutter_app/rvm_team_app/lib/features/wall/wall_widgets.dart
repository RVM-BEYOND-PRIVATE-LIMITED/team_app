import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/team_kit.dart';
import 'bloc/wall_bloc.dart';
import 'praise_sheet.dart';

const wallReactions = <String, String>{
  'like': '👍',
  'love': '❤️',
  'laugh': '😄',
  'clap': '👏',
  'insightful': '💡',
  'curious': '🤔',
};

const wallReactionLabels = <String, String>{
  'like': 'Like',
  'love': 'Love',
  'laugh': 'Haha',
  'clap': 'Applaud',
  'insightful': 'Insightful',
  'curious': 'Curious',
};

/// Facebook-style reaction picker: long-press Like opens this sheet with big
/// emojis. Returns the picked key, or null when dismissed.
Future<String?> showFbReactionPicker(BuildContext context,
    {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('React',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              // Wrap instead of Row: on 320px phones six fixed chips
              // overflowed by ~3px. Wrap centers and flows to a second
              // row when needed, so no device can overflow.
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 2,
                  runSpacing: 8,
                  children: [
                    for (final r in wallReactions.entries)
                      _PickerEmoji(
                        emoji: r.value,
                        label: wallReactionLabels[r.key] ?? r.key,
                        selected: current == r.key,
                        onTap: () => Navigator.pop(context, r.key),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PickerEmoji extends StatelessWidget {
  const _PickerEmoji(
      {required this.emoji,
      required this.label,
      required this.selected,
      required this.onTap});
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Fixed width keeps every label on one line and lets the parent Wrap
    // measure exactly — no RenderFlex overflow on 320px phones.
    return SizedBox(
      width: 52,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Facebook-style summary: overlapping top emojis + total on the left,
/// comments on the right. Tapping the left opens who-reacted.
class FbReactionSummary extends StatelessWidget {
  const FbReactionSummary(
      {super.key,
      this.counts,
      this.total = 0,
      this.commentCount,
      this.onWhoReacted,
      this.onOpen});
  final WallReactionCounts? counts;
  final int total;
  final int? commentCount;
  final VoidCallback? onWhoReacted;
  final VoidCallback? onOpen;

  List<String> get _top {
    final c = counts?.counts ?? const <String, int>{};
    final sorted = c.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.where((e) => e.value > 0).take(3).map((e) => e.key).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (total <= 0 && (commentCount ?? 0) <= 0) {
      return const SizedBox.shrink();
    }
    final text = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          if (total > 0)
            InkWell(
              onTap: onWhoReacted,
              borderRadius: BorderRadius.circular(6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: _top.isEmpty
                        ? 0
                        : 20.0 + (_top.length - 1) * 14.0,
                    height: 22,
                    child: Stack(
                      children: [
                        for (var i = 0; i < _top.length; i++)
                          Positioned(
                            left: i * 14.0,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context).cardColor,
                                border: Border.all(
                                    color: Theme.of(context)
                                        .dividerColor
                                        .withValues(alpha: 0.4)),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                  wallReactions[_top[i]] ?? '👍',
                                  style:
                                      const TextStyle(fontSize: 13)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('$total',
                      style: text?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
                ],
              ),
            ),
          const Spacer(),
          if ((commentCount ?? 0) > 0)
            InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(6),
              child: Text(
                  '$commentCount comment${commentCount == 1 ? '' : 's'}',
                  style: text?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

/// Facebook-style Like + Comment action row. Tap Like toggles 'like',
/// long-press opens the emoji picker. Shows current reaction when set.
class FbPostReactionBar extends StatelessWidget {
  const FbPostReactionBar(
      {super.key,
      this.myReaction,
      required this.onReact,
      required this.onOpen});
  final String? myReaction;
  final ValueChanged<String?> onReact;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final liked = myReaction != null;
    final label =
        myReaction == null ? 'Like' : (wallReactionLabels[myReaction] ?? 'Like');
    final icon = myReaction == null
        ? '👍'
        : (wallReactions[myReaction] ?? '👍');
    return Column(
      children: [
        const Divider(height: 13),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onLongPress: () async {
                  final picked = await showFbReactionPicker(context,
                      current: myReaction);
                  if (picked == null) return;
                  if (picked == myReaction) {
                    onReact(null);
                  } else {
                    onReact(picked);
                  }
                },
                child: TextButton.icon(
                  onPressed: () {
                    if (liked) {
                      onReact(null);
                    } else {
                      onReact('like');
                    }
                  },
                  icon: Text(icon,
                      style: const TextStyle(fontSize: 18)),
                  label: Text(label,
                      style: TextStyle(
                          color: liked
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight:
                              liked ? FontWeight.w700 : FontWeight.w500)),
                ),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: onOpen,
                icon: Icon(Icons.mode_comment_outlined,
                    size: 18, color: scheme.onSurfaceVariant),
                label: Text('Comment',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact Facebook-style bar for comments: summary + Like link with
/// long-press picker.
class FbCommentReactionBar extends StatelessWidget {
  const FbCommentReactionBar(
      {super.key,
      this.counts,
      this.total = 0,
      this.myReaction,
      required this.onReact,
      this.onWhoReacted});
  final WallReactionCounts? counts;
  final int total;
  final String? myReaction;
  final ValueChanged<String?> onReact;
  final VoidCallback? onWhoReacted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (total <= 0 && myReaction == null) {
      // Still offer Like so a comment with no reactions can get one.
      return Row(
        children: [
          _LikeLink(
              myReaction: myReaction,
              onReact: onReact,
              counts: counts,
              total: total),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0)
          InkWell(
            onTap: onWhoReacted,
            borderRadius: BorderRadius.circular(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StackedEmojis(counts: counts),
                const SizedBox(width: 4),
                Text('$total',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        _LikeLink(
            myReaction: myReaction,
            onReact: onReact,
            counts: counts,
            total: total),
      ],
    );
  }
}

class _StackedEmojis extends StatelessWidget {
  const _StackedEmojis({this.counts});
  final WallReactionCounts? counts;

  @override
  Widget build(BuildContext context) {
    final c = counts?.counts ?? const <String, int>{};
    final sorted = c.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top =
        sorted.where((e) => e.value > 0).take(3).map((e) => e.key).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: 18.0 + (top.length - 1) * 12.0,
      height: 20,
      child: Stack(
        children: [
          for (var i = 0; i < top.length; i++)
            Positioned(
              left: i * 12.0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).cardColor,
                  border: Border.all(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.4)),
                ),
                alignment: Alignment.center,
                child: Text(wallReactions[top[i]] ?? '👍',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

class _LikeLink extends StatelessWidget {
  const _LikeLink(
      {this.myReaction, required this.onReact, this.counts, this.total = 0});
  final String? myReaction;
  final ValueChanged<String?> onReact;
  final WallReactionCounts? counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final liked = myReaction != null;
    return GestureDetector(
      onLongPress: () async {
        final picked =
            await showFbReactionPicker(context, current: myReaction);
        if (picked == null) return;
        if (picked == myReaction) {
          onReact(null);
        } else {
          onReact(picked);
        }
      },
      child: TextButton(
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        onPressed: () {
          if (liked) {
            onReact(null);
          } else {
            onReact('like');
          }
        },
        child: Text(
            liked
                ? (wallReactionLabels[myReaction] ?? 'Liked')
                : 'Like',
            style: TextStyle(
                fontSize: 12,
                color: liked ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight:
                    liked ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}

class CelebrationsCard extends StatelessWidget {
  const CelebrationsCard({super.key, required this.celebrations});
  final WallCelebrations celebrations;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Celebrations',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: RvmSpacing.sm),
            for (final c in celebrations.birthdays)
              _CelebrationRow(
                card: c,
                kind: _CelebrationKind.birthday,
                onWish: () => context.read<WallBloc>().add(WallWished(
                      employeeId: c.employee.id,
                      occasion: 'birthday',
                      body: 'Happy birthday!',
                    )),
              ),
            for (final c in celebrations.anniversaries)
              _CelebrationRow(
                card: c,
                kind: _CelebrationKind.anniversary,
                onWish: () => context.read<WallBloc>().add(WallWished(
                      employeeId: c.employee.id,
                      occasion: 'anniversary',
                      body: 'Happy anniversary!',
                    )),
              ),
            for (final c in celebrations.newJoiners)
              _CelebrationRow(
                card: c,
                kind: _CelebrationKind.newJoiner,
                onWish: null,
              ),
            for (final c in celebrations.promotions)
              _CelebrationRow(
                card: c,
                kind: _CelebrationKind.promotion,
                onWish: () => context.read<WallBloc>().add(WallWished(
                      employeeId: c.employee.id,
                      occasion: 'promotion',
                      body: 'Congratulations on your promotion!',
                    )),
              ),
          ],
        ),
      ),
    );
  }
}

/// One celebration kind, one look: birthdays, work anniversaries, promotions
/// and new joiners each carry their own color and icon. Backend `9310fb7`
/// (contract 0.13.0) sends recent promotions and accepts a `promotion` wish.
enum _CelebrationKind { birthday, anniversary, newJoiner, promotion }

extension on _CelebrationKind {
  IconData get icon => switch (this) {
        _CelebrationKind.birthday => Icons.cake_outlined,
        _CelebrationKind.anniversary => Icons.workspace_premium_outlined,
        _CelebrationKind.newJoiner => Icons.waving_hand_outlined,
        _CelebrationKind.promotion => Icons.trending_up_rounded,
      };

  Color get color => switch (this) {
        _CelebrationKind.birthday => RvmColors.danger,
        _CelebrationKind.anniversary => RvmColors.warning,
        _CelebrationKind.newJoiner => RvmColors.success,
        _CelebrationKind.promotion => RvmColors.info,
      };

  Color get soft => switch (this) {
        _CelebrationKind.birthday => RvmColors.dangerSoft,
        _CelebrationKind.anniversary => RvmColors.warningSoft,
        _CelebrationKind.newJoiner => RvmColors.successSoft,
        _CelebrationKind.promotion => RvmColors.infoSoft,
      };

  String label(String? on) => switch (this) {
        _CelebrationKind.birthday =>
          on == null ? 'Birthday' : 'Birthday · $on',
        _CelebrationKind.anniversary =>
          on == null ? 'Work anniversary' : 'Work anniversary · $on',
        _CelebrationKind.newJoiner =>
          on == null ? 'New joiner' : 'New joiner · $on',
        _CelebrationKind.promotion =>
          on == null ? 'Promotion' : 'Promotion · $on',
      };
}

class _CelebrationRow extends StatelessWidget {
  const _CelebrationRow({required this.card, required this.kind, this.onWish});
  final CelebrationCard card;
  final _CelebrationKind kind;
  final VoidCallback? onWish;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(
        backgroundColor: kind.soft,
        child: Icon(kind.icon, color: kind.color, size: 20),
      ),
      title: Text(card.employee.fullName),
      subtitle: Text(
        [
          kind.label(card.on),
          if (card.wishCount > 0) '${card.wishCount} wishes',
        ].join(' · '),
      ),
      trailing: onWish == null
          ? Icon(Icons.check_circle, color: kind.color.withValues(alpha: 0.35))
          : card.wishedByMe
              ? const Icon(Icons.check_circle, color: RvmColors.success)
              : TextButton(onPressed: onWish, child: const Text('Wish')),
    );
  }
}

/// RVM's twelve praise badges, grouped by what they are about
/// (`for` in `policy/wall.js`), each with its own icon so staff can tell at a
/// glance what every badge means.
const _badgeGroupIcons = <String, IconData>{
  'teaching': Icons.menu_book_outlined,
  'placement': Icons.rocket_launch_outlined,
  'teamwork': Icons.groups_outlined,
  'care': Icons.favorite_outline,
  'effort': Icons.bolt_outlined,
  'people': Icons.diversity_3_outlined,
  'outreach': Icons.campaign_outlined,
  'quality': Icons.verified_outlined,
};

/// A card in the feed that lists every badge and opens the praise sheet with
/// the tapped badge preselected, so giving a badge to a colleague takes one
/// tap from the Wall.
class GivePraiseCard extends StatelessWidget {
  const GivePraiseCard({super.key, required this.badges});
  final List<PraiseBadge> badges;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const TeamIconBadge(
                    icon: Icons.emoji_events_outlined,
                    color: RvmColors.teamSeed,
                    background: RvmColors.claySoft),
                const SizedBox(width: RvmSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Give praise',
                          style:
                              Theme.of(context).textTheme.titleMedium),
                      Text('Award a badge to a colleague',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: RvmSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in badges)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      _badgeGroupIcons[b.forGroup] ??
                          Icons.emoji_events_outlined,
                      size: 15,
                      color: RvmColors.teamSeed,
                    ),
                    label: Text(b.label,
                        style: const TextStyle(fontSize: 11.5)),
                    onPressed: () =>
                        showPraiseSheet(context, initialBadge: b.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({super.key, required this.announcement});
  final WallAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final read = announcement.readAt != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(announcement.title,
                        style: Theme.of(context).textTheme.titleMedium)),
                if (announcement.pinned) const Icon(Icons.push_pin, size: 16),
              ],
            ),
            const SizedBox(height: 6),
            Text(announcement.body),
            if (announcement.needsAck) ...[
              const SizedBox(height: RvmSpacing.sm),
              if (announcement.acked)
                Row(children: const [
                  Icon(Icons.verified_outlined,
                      size: 16, color: RvmColors.success),
                  SizedBox(width: 4),
                  Text('Acknowledged')
                ])
              else
                FilledButton.tonal(
                  onPressed: () => context
                      .read<WallBloc>()
                      .add(WallAnnouncementAcked(announcement.id)),
                  child: const Text('Acknowledge'),
                ),
            ] else if (!read)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context
                      .read<WallBloc>()
                      .add(WallAnnouncementRead(announcement.id)),
                  child: const Text('Mark read'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class WallPostCard extends StatelessWidget {
  const WallPostCard({
    super.key,
    required this.post,
    required this.onReact,
    required this.onOpen,
    this.onEdit,
    this.onDelete,
    this.onReport,
    this.onWhoReacted,
    this.onPollChanged,
  });
  final WallPost post;
  final ValueChanged<String?> onReact;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final VoidCallback? onWhoReacted;
  final VoidCallback? onPollChanged;

  @override
  Widget build(BuildContext context) {
    // Compact by design (KP): tight padding and gaps so more of the feed fits
    // on one screen, with the author's role on the meta line for context.
    final meta = [
      _when(post.createdAt),
      if (post.author?.designation != null &&
          post.author!.designation!.isNotEmpty)
        post.author!.designation!,
    ].where((s) => s.isNotEmpty).join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(name: post.author?.fullName ?? '?'),
                const SizedBox(width: RvmSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.author?.fullName ?? 'Someone',
                          style: Theme.of(context).textTheme.titleSmall),
                      if (meta.isNotEmpty)
                        Text(meta,
                            style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
                if (post.kind == 'praise')
                  _Chip(
                      label: post.badgeLabel ?? 'Praise',
                      color: RvmColors.teamSeed)
                else if (post.kind == 'poll')
                  const _Chip(label: 'Poll', color: RvmColors.brand),
                if (onEdit != null || onDelete != null || onReport != null)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (v) {
                      if (v == 'edit') onEdit?.call();
                      if (v == 'delete') onDelete?.call();
                      if (v == 'report') onReport?.call();
                    },
                    itemBuilder: (_) => [
                      if (onEdit != null)
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (onDelete != null)
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                      if (onReport != null)
                        const PopupMenuItem(
                            value: 'report', child: Text('Report')),
                    ],
                  ),
              ],
            ),
            if (post.body != null && post.body!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(post.body!),
            ],
            if (post.isPraise && post.about != null) ...[
              const SizedBox(height: 4),
              Text('For ${post.about!.fullName}',
                  style: Theme.of(context).textTheme.bodySmall),
            ]
            else if (post.kind == 'wish' && post.about != null) ...[
              const SizedBox(height: 4),
              Text(
                [
                  'For ${post.about!.fullName}',
                  if (post.occasion == 'birthday')
                    'Birthday'
                  else if (post.occasion == 'anniversary')
                    'Work anniversary',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall),
            ],
            if (post.poll != null) ...[
              const SizedBox(height: 6),
              _PollBlock(
                  poll: post.poll!,
                  postId: post.id,
                  mine: post.mine,
                  onChanged: onPollChanged ?? () {}),
            ],
            // Facebook-style: summary (stacked emojis + total · comments)
            // then Like | Comment actions. Long-press Like opens the picker.
            FbReactionSummary(
              counts: post.reactions,
              total: post.reactions?.total ?? 0,
              commentCount: post.commentCount,
              onWhoReacted: onWhoReacted,
              onOpen: onOpen,
            ),
            FbPostReactionBar(
              myReaction: post.myReaction,
              onReact: onReact,
              onOpen: onOpen,
            ),
          ],
        ),
      ),
    );
  }

  static String _when(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${local.day}/${local.month}';
  }
}

class _PollBlock extends StatelessWidget {
  const _PollBlock(
      {required this.poll,
      required this.postId,
      required this.mine,
      required this.onChanged});
  final WallPoll poll;
  final String postId;
  final bool mine;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final total = poll.totalVotes == 0 ? 1 : poll.totalVotes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in poll.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: OutlinedButton(
              onPressed: poll.closed
                  ? null
                  : () {
                      final ids = poll.myOptionIds.contains(o.id)
                          ? (poll.myOptionIds.where((x) => x != o.id).toList())
                          : ([...poll.myOptionIds, o.id]);
                      if (ids.isEmpty) return;
                      context
                          .read<WallBloc>()
                          .add(WallPollVoted(pollId: postId, optionIds: ids));
                    },
              child: Row(
                children: [
                  Expanded(child: Text(o.label, textAlign: TextAlign.left)),
                  Text('${o.votes} · ${(o.votes * 100 / total).round()}%'),
                ],
              ),
            ),
          ),
        Text(
          poll.closed
              ? 'Poll closed'
              : '${poll.totalVotes} vote${poll.totalVotes == 1 ? '' : 's'}${poll.closesOn != null ? ' · closes ${poll.closesOn}' : ''}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        if (!poll.closed && poll.myOptionIds.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                try {
                  await getIt<EssRepository>().withdrawPollVote(postId);
                  onChanged();
                } on Failure catch (f) {
                  if (context.mounted) _snack(context, f.message);
                }
              },
              child: const Text('Withdraw my vote'),
            ),
          ),
        if (mine && !poll.closed)
          Wrap(
            spacing: 8,
            children: [
              if (!poll.optionsLocked)
                TextButton(
                    onPressed: () => _addOption(context),
                    child: const Text('Add option')),
              TextButton(
                  onPressed: () => _close(context),
                  child: const Text('Close poll')),
            ],
          ),
      ],
    );
  }

  Future<void> _addOption(BuildContext context) async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add an option'),
        content: TextField(
            controller: controller,
            maxLength: 120,
            decoration: const InputDecoration(hintText: 'Option')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (label == null || label.isEmpty || !context.mounted) return;
    try {
      await getIt<EssRepository>().addPollOption(postId, label);
      onChanged();
    } on Failure catch (f) {
      if (context.mounted) _snack(context, f.message);
    }
  }

  Future<void> _close(BuildContext context) async {
    try {
      await getIt<EssRepository>().closePoll(postId);
      onChanged();
    } on Failure catch (f) {
      if (context.mounted) _snack(context, f.message);
    }
  }

  static void _snack(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final s = name.trim();
    return CircleAvatar(
        child: Text(s.isEmpty ? '?' : s.substring(0, 1).toUpperCase()));
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      );
}

/// F2: "who reacted" for one post, grouped by reaction.
class ReactionBreakdownSheet extends StatefulWidget {
  const ReactionBreakdownSheet({super.key, this.postId, this.commentId})
      : assert(postId != null || commentId != null);
  final String? postId;
  final String? commentId;

  @override
  State<ReactionBreakdownSheet> createState() => _ReactionBreakdownSheetState();
}

class _ReactionBreakdownSheetState extends State<ReactionBreakdownSheet> {
  bool _loading = true;
  String? _error;
  List<WallReactionGroup> _groups = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = getIt<EssRepository>();
      final groups = widget.postId != null
          ? await repo.postReactions(widget.postId!)
          : await repo.commentReactions(widget.commentId!);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _error = f.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                RvmSpacing.md, 0, RvmSpacing.md, RvmSpacing.sm),
            child: Text('Who reacted',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: Center(child: Text(_error!)))
          else if (_groups.isEmpty)
            const Expanded(child: Center(child: Text('No reactions yet.')))
          else
            Expanded(
              child: ListView(
                children: [
                  for (final g in _groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          RvmSpacing.md, RvmSpacing.sm, RvmSpacing.md, 2),
                      child: Text(
                          '${wallReactions[g.reaction] ?? g.reaction} ${g.count}',
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    for (final p in g.people)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                            child: Text(p.fullName.isEmpty
                                ? '?'
                                : p.fullName.substring(0, 1).toUpperCase())),
                        title: Text(p.fullName),
                        subtitle: p.employeeCode == null
                            ? null
                            : Text(p.employeeCode!),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

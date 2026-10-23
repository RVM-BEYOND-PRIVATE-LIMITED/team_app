import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import 'bloc/wall_bloc.dart';

const wallReactions = <String, String>{
  'like': '👍',
  'love': '❤️',
  'laugh': '😄',
  'clap': '👏',
  'insightful': '💡',
  'curious': '🤔',
};

class CelebrationsCard extends StatelessWidget {
  const CelebrationsCard({super.key, required this.celebrations});
  final WallCelebrations celebrations;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final c in celebrations.birthdays) (c, 'birthday'),
      for (final c in celebrations.anniversaries) (c, 'anniversary'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Celebrations',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: RvmSpacing.sm),
            for (final entry in cards)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _Avatar(name: entry.$1.employee.fullName),
                title: Text(entry.$1.employee.fullName),
                subtitle: Text(
                    entry.$2 == 'birthday' ? 'Birthday' : 'Work anniversary'),
                trailing: entry.$1.wishedByMe
                    ? const Icon(Icons.check_circle, color: RvmColors.success)
                    : TextButton(
                        onPressed: () =>
                            context.read<WallBloc>().add(WallWished(
                                  employeeId: entry.$1.employee.id,
                                  occasion: entry.$2,
                                  body: entry.$2 == 'birthday'
                                      ? 'Happy birthday!'
                                      : 'Happy anniversary!',
                                )),
                        child: const Text('Wish'),
                      ),
              ),
            for (final c in celebrations.newJoiners)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _Avatar(name: c.employee.fullName),
                title: Text(c.employee.fullName),
                subtitle: Text('New joiner${c.on != null ? ' · ${c.on}' : ''}'),
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
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
                      Text(_when(post.createdAt),
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
              const SizedBox(height: RvmSpacing.sm),
              Text(post.body!),
            ],
            if (post.isPraise && post.about != null) ...[
              const SizedBox(height: 6),
              Text('For ${post.about!.fullName}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (post.poll != null) ...[
              const SizedBox(height: RvmSpacing.sm),
              _PollBlock(
                  poll: post.poll!,
                  postId: post.id,
                  mine: post.mine,
                  onChanged: onPollChanged ?? () {}),
            ],
            const SizedBox(height: RvmSpacing.sm),
            Row(
              children: [
                // Six reaction chips can be wider than a phone once the two
                // action buttons are beside them. Give the wrap the remaining
                // width instead of letting the Row overflow (a RenderFlex
                // overflow is a FlutterError on every rebuild).
                Expanded(
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      for (final r in wallReactions.entries)
                        InkWell(
                          onTap: () =>
                              onReact(post.myReaction == r.key ? null : r.key),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: post.myReaction == r.key
                                  ? scheme.primaryContainer
                                  : null,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                                '${r.value}${post.reactions?.counts[r.key] ?? 0}',
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ),
                    ],
                  ),
                ),
                if ((post.reactions?.total ?? 0) > 0)
                  TextButton.icon(
                    onPressed: onWhoReacted,
                    icon: const Icon(Icons.groups_outlined, size: 16),
                    label: Text('${post.reactions!.total}'),
                  ),
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.mode_comment_outlined, size: 16),
                  label: Text('${post.commentCount}'),
                ),
              ],
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

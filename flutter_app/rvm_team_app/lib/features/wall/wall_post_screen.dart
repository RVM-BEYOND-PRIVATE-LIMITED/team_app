import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import 'mention_picker.dart';
import 'wall_widgets.dart';

/// One Wall post with its comments and one level of replies (F1/F2).
class WallPostScreen extends StatefulWidget {
  const WallPostScreen({super.key, required this.postId});
  final String postId;

  @override
  State<WallPostScreen> createState() => _WallPostScreenState();
}

class _WallPostScreenState extends State<WallPostScreen> {
  final _comment = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  Failure? _failure;
  WallPostDetail? _detail;
  String? _replyTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await getIt<EssRepository>().wallPost(widget.postId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _failure = null;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _failure = f;
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await getIt<EssRepository>().addWallComment(postId: widget.postId, body: text, parentId: _replyTo);
      _comment.clear();
      _replyTo = null;
      await _load();
    } on Failure catch (f) {
      if (mounted) {
        ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(f.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _react(String reaction) async {
    try {
      final repo = getIt<EssRepository>();
      final current = _detail?.post.myReaction;
      if (current == reaction) {
        await repo.unreactToPost(widget.postId);
      } else {
        await repo.reactToPost(widget.postId, reaction);
      }
      await _load();
    } on Failure {
      // Best effort.
    }
  }

  Future<void> _reactComment(WallComment comment, String? reaction) async {
    try {
      final repo = getIt<EssRepository>();
      if (reaction == null || comment.myReaction == reaction) {
        await repo.unreactToComment(comment.id);
      } else {
        await repo.reactToComment(comment.id, reaction);
      }
      await _load();
    } on Failure catch (f) {
      if (mounted) _snack(f.message);
    }
  }

  Future<void> _editComment(WallComment comment) async {
    final controller = TextEditingController(text: comment.body ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit comment'),
        content: TextField(controller: controller, minLines: 2, maxLines: 6, maxLength: 1000),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    try {
      await getIt<EssRepository>().editWallComment(comment.id, text);
      await _load();
    } on Failure catch (f) {
      _snack(f.message);
    }
  }

  Future<void> _deleteComment(WallComment comment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this comment?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await getIt<EssRepository>().deleteWallComment(comment.id);
      await _load();
    } on Failure catch (f) {
      _snack(f.message);
    }
  }

  Future<void> _reportComment(WallComment comment) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Report this comment'),
        content: TextField(controller: controller, minLines: 2, maxLines: 4, maxLength: 280, decoration: const InputDecoration(hintText: 'Why are you reporting it?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Report')),
        ],
      ),
    );
    if (reason == null || reason.length < 3 || !mounted) return;
    try {
      await getIt<EssRepository>().reportComment(comment.id, reason: reason);
      _snack('Reported to HR.');
    } on Failure catch (f) {
      _snack(f.message);
    }
  }

  void _whoReactedComment(WallComment comment) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => ReactionBreakdownSheet(commentId: comment.id),
      );

  void _snack(String message) =>
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const TeamPageHeader(title: 'Post', subtitle: Text('Comments and replies')),
          Expanded(child: _body()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _comment,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: _replyTo == null ? 'Write a comment…' : 'Reply to a comment…',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Mention',
                    onPressed: () async {
                      final tag = await pickMention(context);
                      if (tag == null || !mounted) return;
                      setState(() {
                        _comment.text = _comment.text.isEmpty ? tag : '${_comment.text} $tag';
                        _comment.selection = TextSelection.collapsed(offset: _comment.text.length);
                      });
                    },
                    icon: const Icon(Icons.alternate_email),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) return AppError(message: _failure!.message, onRetry: _load);
    final detail = _detail!;
    return ListView(
      padding: const EdgeInsets.all(RvmSpacing.md),
      children: [
        WallPostCard(
          post: detail.post,
          onReact: (reaction) {
            if (reaction != null) _react(reaction);
          },
          onOpen: () {},
          onWhoReacted: (detail.post.reactions?.total ?? 0) > 0
              ? () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => ReactionBreakdownSheet(postId: widget.postId),
                  )
              : null,
          onPollChanged: _load,
        ),
        const SizedBox(height: RvmSpacing.md),
        Text('Comments (${detail.post.commentCount})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: RvmSpacing.sm),
        if (detail.comments.isEmpty)
          const Text('No comments yet.')
        else
          for (final c in detail.comments) ...[
            _CommentTile(
              comment: c,
              onReply: () => setState(() => _replyTo = c.id),
              onReact: (reaction) => _reactComment(c, reaction),
              onEdit: c.mine ? () => _editComment(c) : null,
              onDelete: c.mine ? () => _deleteComment(c) : null,
              onReport: c.mine ? null : () => _reportComment(c),
              onWhoReacted: (c.reactions?.total ?? 0) > 0 ? () => _whoReactedComment(c) : null,
            ),
            for (final r in c.replies)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 6),
                child: _CommentTile(
                  comment: r,
                  onReply: null,
                  onReact: (reaction) => _reactComment(r, reaction),
                  onEdit: r.mine ? () => _editComment(r) : null,
                  onDelete: r.mine ? () => _deleteComment(r) : null,
                  onReport: r.mine ? null : () => _reportComment(r),
                  onWhoReacted: (r.reactions?.total ?? 0) > 0 ? () => _whoReactedComment(r) : null,
                ),
              ),
            const SizedBox(height: RvmSpacing.sm),
          ],
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.onReply,
    required this.onReact,
    this.onEdit,
    this.onDelete,
    this.onReport,
    this.onWhoReacted,
  });
  final WallComment comment;
  final VoidCallback? onReply;
  final ValueChanged<String?> onReact;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final VoidCallback? onWhoReacted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  child: Text(comment.author?.fullName.isNotEmpty == true
                      ? comment.author!.fullName.substring(0, 1).toUpperCase()
                      : '?'),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(comment.author?.fullName ?? 'Someone', style: Theme.of(context).textTheme.titleSmall)),
                if (onReply != null) TextButton(onPressed: onReply, child: const Text('Reply')),
                if (onEdit != null || onDelete != null || onReport != null)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (v) {
                      if (v == 'edit') onEdit?.call();
                      if (v == 'delete') onDelete?.call();
                      if (v == 'report') onReport?.call();
                    },
                    itemBuilder: (_) => [
                      if (onEdit != null) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (onDelete != null) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      if (onReport != null) const PopupMenuItem(value: 'report', child: Text('Report')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(comment.hidden ? 'Hidden by HR' : (comment.body ?? '')),
            if (!comment.hidden) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 2,
                children: [
                  for (final r in wallReactions.entries)
                    InkWell(
                      onTap: () => onReact(comment.myReaction == r.key ? null : r.key),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: comment.myReaction == r.key ? scheme.primaryContainer : null,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('${r.value}${comment.reactions?.counts[r.key] ?? 0}', style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                ],
              ),
              if ((comment.reactions?.total ?? 0) > 0 && onWhoReacted != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onWhoReacted,
                    icon: const Icon(Icons.groups_outlined, size: 14),
                    label: Text('${comment.reactions!.total}'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

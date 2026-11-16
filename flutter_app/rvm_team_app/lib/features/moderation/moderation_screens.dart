import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../domain/team_stage2_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import '../stage2/stage2_shared.dart';

/// `/moderation` — reported posts, hide/restore/warn (#58 items 8–10).
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});
  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  Future<List<ModerationReport>>? _future;
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().moderationReports());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Moderation'),
        actions: [
          IconButton(
              tooltip: 'Moderation log',
              onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text('Moderation log',
                            style: Theme.of(context).textTheme.titleLarge),
                        for (final line in _log.reversed)
                          ListTile(dense: true, title: Text(line)),
                        if (_log.isEmpty) const Text('No action in this session.'),
                      ],
                    ),
                  ),
              icon: const Icon(Icons.history)),
          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<List<ModerationReport>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return stage2Failure(
                snapshot.error is Failure ? snapshot.error as Failure : null,
                onRetry: _load);
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) return stage2Empty('No reported post.');
          return ListView.separated(
            padding: const EdgeInsets.all(RvmSpacing.md),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
            itemBuilder: (_, i) {
              final r = rows[i];
              return TeamCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(r.group,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        TeamPill(
                            label: r.hidden ? 'Hidden' : 'Visible',
                            tone: r.hidden
                                ? TeamPillTone.danger
                                : TeamPillTone.neutral,
                            dense: true),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(r.postText, maxLines: 4, overflow: TextOverflow.ellipsis),
                    Text('${r.reports} reports',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: p.muted)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (r.hidden)
                          TextButton(
                              onPressed: () => _restore(r),
                              child: const Text('Restore')),
                        TextButton(
                            onPressed: () => _hide(r),
                            child: const Text('Keep hidden')),
                        TextButton(
                            onPressed: () => _warn(r),
                            child: const Text('Warn')),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _hide(ModerationReport r) async {
    final reason = await _reason(context, 'Why keep it hidden?');
    if (reason == null) return;
    try {
      await stage2Repository().hidePost(r.postId, reason,
          key: 'hide-${DateTime.now().microsecondsSinceEpoch}');
      _add('Hidden ${r.postId} · $reason');
    } on Failure catch (failure) {
      _snack(failure.message);
    }
  }

  Future<void> _restore(ModerationReport r) async {
    try {
      await stage2Repository().restorePost(r.postId,
          note: 'Restored from the Team app',
          key: 'restore-${DateTime.now().microsecondsSinceEpoch}');
      _add('Restored ${r.postId}');
    } on Failure catch (failure) {
      _snack(failure.message);
    }
  }

  Future<void> _warn(ModerationReport r) async {
    final reason = await _reason(context, 'Why warn the author?');
    if (reason == null) return;
    try {
      await stage2Repository().warnMember(r.id,
          reason: reason,
          postId: r.postId,
          key: 'warn-${DateTime.now().microsecondsSinceEpoch}');
      _add('Warned the author of ${r.postId} · $reason');
    } on Failure catch (failure) {
      _snack(failure.message);
    }
  }

  void _add(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
    _snack(line);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _reason(BuildContext context, String title) async {
    final c = TextEditingController();
    final out = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Reason (required)')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(c.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    return out != null && out.length >= 3 ? out : null;
  }
}

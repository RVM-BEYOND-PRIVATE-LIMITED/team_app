import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/team_stage2_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import '../stage2/stage2_shared.dart';

/// `/complaints` — the Admin Manager's queue and the HoO's escalated list (#58).
class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});
  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  String _filter = 'open';
  Future<List<ComplaintRow>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(
      () => _future = stage2Repository().complaints(filter: _filter));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Complaints'),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(RvmSpacing.md),
            child: Row(
              children: [
                for (final f in ['open', 'overdue', 'resolved', 'all'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: _filter == f,
                      label: Text(f[0].toUpperCase() + f.substring(1)),
                      onSelected: (_) {
                        _filter = f;
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ComplaintRow>>(
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
                if (rows.isEmpty) return stage2Empty('No complaints in $_filter.');
                return ListView.separated(
                  padding: const EdgeInsets.all(RvmSpacing.md),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: RvmSpacing.sm),
                  itemBuilder: (_, i) {
                    final c = rows[i];
                    return TeamCard(
                      onTap: () => context
                          .push('/complaints/${c.id}')
                          .then((_) => _load()),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(c.category,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700)),
                              ),
                              if (c.reopened)
                                const TeamPill(label: 'Reopened', dense: true),
                              if (c.overdueResolve)
                                TeamPill(
                                    label: 'Past 48h',
                                    tone: TeamPillTone.danger,
                                    dense: true),
                            ],
                          ),
                          Text('${c.studentName} · ${c.course} · ${c.batch}'),
                          Text(
                            '${c.status} · reply ${stage2DateTime(c.replyDue)}'
                            '${c.overdueReply ? ' (overdue)' : ''}'
                            ' · resolve ${stage2DateTime(c.resolveDue)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// `/complaints/:id` — the thread, reply and resolve (#58 item 3).
class ComplaintThreadScreen extends StatefulWidget {
  const ComplaintThreadScreen({super.key, required this.id});
  final String id;
  @override
  State<ComplaintThreadScreen> createState() => _ComplaintThreadScreenState();
}

class _ComplaintThreadScreenState extends State<ComplaintThreadScreen> {
  Future<ComplaintThread>? _future;
  final _reply = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  void _load() => setState(
      () => _future = stage2Repository().complaint(widget.id));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Complaint'),
        actions: [
          IconButton(
              tooltip: 'Resolve',
              onPressed: _busy ? null : _resolve,
              icon: const Icon(Icons.task_alt)),
        ],
      ),
      body: FutureBuilder<ComplaintThread>(
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
          final thread = snapshot.data!;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(RvmSpacing.md),
                  children: [
                    TeamCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(thread.complaint.category,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge),
                              ),
                              if (thread.complaint.reopened)
                                const TeamPill(label: 'Reopened'),
                            ],
                          ),
                          Text(
                              '${thread.complaint.studentName} · ${thread.complaint.course} · ${thread.complaint.batch}'),
                          Text(
                              'Reply due ${stage2DateTime(thread.complaint.replyDue)}'
                              ' · Resolve due ${stage2DateTime(thread.complaint.resolveDue)}',
                              style: Theme.of(context).textTheme.bodySmall),
                          if (thread.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(thread.description),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: RvmSpacing.md),
                    for (final m in thread.messages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TeamCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.author.toUpperCase(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: p.muted)),
                              Text(m.body),
                              Text(stage2DateTime(m.createdAt),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: p.subtle)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(RvmSpacing.md),
                  child: Column(
                    children: [
                      if (_error != null)
                        Text(_error!, style: TextStyle(color: p.danger)),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _reply,
                              minLines: 1,
                              maxLines: 3,
                              decoration:
                                  const InputDecoration(hintText: 'Reply to the student'),
                            ),
                          ),
                          IconButton(
                            onPressed: _busy ? null : _send,
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _send() async {
    if (_reply.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await stage2Repository().replyComplaint(widget.id, _reply.text.trim(),
          key: 'complaint-reply-${DateTime.now().microsecondsSinceEpoch}');
      _reply.clear();
      _load();
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve() async {
    final c = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resolve with a note'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'What was done?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(c.text.trim()),
              child: const Text('Resolve')),
        ],
      ),
    );
    c.dispose();
    if (note == null || note.length < 3) return;
    try {
      await stage2Repository().setComplaintStatus(widget.id,
          status: 'resolved',
          note: note,
          key: 'complaint-resolve-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Complaint resolved.')));
        _load();
      }
    } on Failure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }
}

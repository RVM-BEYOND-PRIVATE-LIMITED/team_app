import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/team_stage2_models.dart';
import '../../injection.dart';
import '../../platform/call_launcher.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import '../stage2/stage2_shared.dart';

/// `/placement` — today's company follow-ups and the proof queue (#56).
class PlacementHomeScreen extends StatefulWidget {
  const PlacementHomeScreen({super.key});
  @override
  State<PlacementHomeScreen> createState() => _PlacementHomeScreenState();
}

class _PlacementHomeScreenState extends State<PlacementHomeScreen> {
  Future<(List<PlacementFollowup>, List<PlacementVerification>)>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _future = _loadAll();
      });

  Future<(List<PlacementFollowup>, List<PlacementVerification>)> _loadAll() async {
    final repo = stage2Repository();
    final follows = await repo.companyFollowups();
    final tasks = await repo.verifications();
    return (follows, tasks);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Placement'),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<(List<PlacementFollowup>, List<PlacementVerification>)>(
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
          final (follows, tasks) = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(RvmSpacing.md),
            children: [
              Stage2Section(title: 'Company follow-ups today', children: [
                if (follows.isEmpty) TeamCard(child: Text('No company call today.')),
                for (final f in follows)
                  TeamCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.companyName ?? 'Company',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              Text('${f.phoneMasked ?? 'masked'} · ${f.status ?? 'open'}'),
                              if (f.latestRemark != null)
                                Text('“${f.latestRemark}”',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        IconButton(
                            tooltip: 'Call',
                            onPressed: () => _call(f),
                            icon: Icon(Icons.call_outlined, color: p.primary)),
                      ],
                    ),
                  ),
              ]),
              const SizedBox(height: RvmSpacing.lg),
              Stage2Section(title: 'Proof checks', children: [
                if (tasks.isEmpty) TeamCard(child: Text('No proof is waiting.')),
                for (final t in tasks)
                  TeamCard(
                    onTap: () => context
                        .push('/placement/verify/${t.id}')
                        .then((_) => _load()),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.studentName ?? 'Student',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text('${t.company ?? ''} · ${t.role ?? ''} · ${t.source}'),
                        Text(
                            '${t.ageDays} days old'
                            '${t.flagged ? ' · flagged' : ''}'
                            '${t.hasProof ? ' · proof attached' : ''}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Future<void> _call(PlacementFollowup f) async {
    try {
      final result = await getIt<CallLauncher>().dial(() =>
          stage2Repository().revealCompany(f.entryId,
              key: 'company-reveal-${DateTime.now().microsecondsSinceEpoch}'));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      final outcome = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _CompanyOutcomeSheet(entryId: f.entryId),
      );
      if (outcome == null) return;
      await stage2Repository().recordCompanyCall(f.entryId,
          outcome: outcome['outcome'] as String,
          status: outcome['status'] as String,
          inProgressState: outcome['in_progress_state'] as String?,
          nextFollowUpOn: outcome['next_follow_up_on'] as String?,
          remark: outcome['remark'] as String?,
          key: 'company-call-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) _load();
    } on Failure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }
}

class _CompanyOutcomeSheet extends StatefulWidget {
  const _CompanyOutcomeSheet({required this.entryId});
  final String entryId;
  @override
  State<_CompanyOutcomeSheet> createState() => _CompanyOutcomeSheetState();
}

class _CompanyOutcomeSheetState extends State<_CompanyOutcomeSheet> {
  String _outcome = 'connected';
  String _status = 'in_progress';
  String _state = 'campus arranged';
  String? _next = stage2Day(DateTime.now().add(const Duration(days: 1)));
  final _remark = TextEditingController();

  @override
  void dispose() {
    _remark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20,
          MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Company call', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _outcome,
            decoration: const InputDecoration(labelText: 'Outcome'),
            items: const [
              DropdownMenuItem(value: 'connected', child: Text('Connected')),
              DropdownMenuItem(value: 'not_connected', child: Text('Not connected')),
            ],
            onChanged: (v) => setState(() => _outcome = v!),
          ),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
              DropdownMenuItem(value: 'converted', child: Text('Converted')),
              DropdownMenuItem(value: 'not_converted', child: Text('Not converted')),
            ],
            onChanged: (v) => setState(() => _status = v!),
          ),
          if (_status == 'in_progress') ...[
            DropdownButtonFormField<String>(
              initialValue: _state,
              decoration: const InputDecoration(labelText: 'In-progress state'),
              items: const [
                DropdownMenuItem(value: 'campus arranged', child: Text('Campus arranged')),
                DropdownMenuItem(value: 'walk-in arranged', child: Text('Walk-in arranged')),
                DropdownMenuItem(value: 'virtual campus arranged', child: Text('Virtual campus arranged')),
                DropdownMenuItem(value: 'no vacancy', child: Text('No vacancy')),
                DropdownMenuItem(value: 'vacancy available', child: Text('Vacancy available')),
                DropdownMenuItem(value: 'other vacancy', child: Text('Other vacancy')),
              ],
              onChanged: (v) => setState(() => _state = v!),
            ),
            OutlinedButton(
              onPressed: _pickDate,
              child: Text('Next follow-up: ${_next ?? 'pick'}'),
            ),
          ],
          TextField(
            controller: _remark,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Remark'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              if (_outcome == 'connected' && _remark.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('A connected call needs a remark.')));
                return;
              }
              Navigator.of(context).pop({
                'outcome': _outcome,
                'status': _status,
                'in_progress_state': _status == 'in_progress' ? _state : null,
                'next_follow_up_on': _status == 'in_progress' ? _next : null,
                'remark': _remark.text.trim(),
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await pickStage2Date(context,
        DateTime.now().add(const Duration(days: 1)),
        first: DateTime.now());
    if (date != null) setState(() => _next = stage2Day(date));
  }
}

/// `/placement/verify/:id` — proof detail, calls and the decision (#56).
class PlacementVerifyScreen extends StatefulWidget {
  const PlacementVerifyScreen({super.key, required this.id});
  final String id;
  @override
  State<PlacementVerifyScreen> createState() => _PlacementVerifyScreenState();
}

class _PlacementVerifyScreenState extends State<PlacementVerifyScreen> {
  PlacementVerification? _task;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await stage2Repository().verifications(status: 'pending');
      final flagged = await stage2Repository().verifications(status: 'flagged');
      final done = await stage2Repository().verifications(status: 'done');
      final all = [...rows, ...flagged, ...done];
      if (mounted) {
        setState(() => _task = all.where((t) => t.id == widget.id).firstOrNull);
      }
    } on Failure catch (failure) {
      if (mounted) setState(() => _message = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    return Scaffold(
      appBar: AppBar(title: const Text('Proof check')),
      body: task == null
          ? const AppLoading()
          : ListView(
              padding: const EdgeInsets.all(RvmSpacing.md),
              children: [
                TeamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.studentName ?? 'Student',
                          style: Theme.of(context).textTheme.titleLarge),
                      Text('${task.company ?? ''} · ${task.role ?? ''}'),
                      Text('Source: ${task.source} · ${task.ageDays} days'),
                      if (task.flagged)
                        Text('Flagged: older than 14 days',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      Text(task.hasProof
                          ? 'Proof attached · open in the secure viewer on the server'
                          : 'No proof from the student'),
                    ],
                  ),
                ),
                const SizedBox(height: RvmSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _call(kind: 'student', outcome: 'confirmed'),
                        child: const Text('Call student'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _call(kind: 'company', outcome: 'confirmed'),
                        child: const Text('Call company'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RvmSpacing.md),
                FilledButton(
                  onPressed: _busy ? null : () => _decide(true),
                  child: const Text('Approve'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Reject'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!),
                ],
              ],
            ),
    );
  }

  Future<void> _call({required String kind, required String outcome}) async {
    setState(() => _busy = true);
    try {
      await stage2Repository().placementCall(widget.id,
          kind: kind,
          outcome: outcome,
          key: 'place-call-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) setState(() => _message = 'Call logged.');
    } on Failure catch (failure) {
      if (mounted) setState(() => _message = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(bool approve) async {
    final note = await _note(context);
    if (note == null) return;
    setState(() => _busy = true);
    try {
      final out = await stage2Repository().decidePlacement(widget.id,
          approve: approve,
          note: note,
          key: 'place-decide-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) {
        setState(() => _message =
            'Saved. Reward: ${out['reward_created'] == true ? 'created' : out['already_rewarded'] == true ? 'already paid' : 'not created'}');
      }
    } on Failure catch (failure) {
      if (mounted) setState(() => _message = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _note(BuildContext context) async {
    final c = TextEditingController();
    final out = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add a note'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Note (required)')),
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

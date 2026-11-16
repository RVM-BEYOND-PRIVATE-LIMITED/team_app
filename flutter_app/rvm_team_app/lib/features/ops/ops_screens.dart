import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/team_stage2_models.dart';
import '../../platform/call_launcher.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import '../stage2/stage2_shared.dart';

/// `/ops` — the Admin Manager's pending counts and branch health (#53).
class OpsHomeScreen extends StatefulWidget {
  const OpsHomeScreen({super.key});
  @override
  State<OpsHomeScreen> createState() => _OpsHomeScreenState();
}

class _OpsHomeScreenState extends State<OpsHomeScreen> {
  Future<(List<PendingCount>, BranchHealth, BranchHealthMoney?)>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _future = _loadAll();
      });

  Future<(List<PendingCount>, BranchHealth, BranchHealthMoney?)> _loadAll() async {
    final repo = stage2Repository();
    final counts = await repo.pendingCounts();
    final health = await repo.branchHealth();
    BranchHealthMoney? money;
    try {
      money = await repo.branchHealthMoney();
    } catch (_) {
      money = null;
    }
    return (counts, health, money);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Operations'),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<(List<PendingCount>, BranchHealth, BranchHealthMoney?)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading(label: 'Loading counts…');
          }
          if (snapshot.hasError) {
            return stage2Failure(
                snapshot.error is Failure ? snapshot.error as Failure : null,
                onRetry: _load);
          }
          final (counts, health, money) = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(RvmSpacing.md),
            children: [
              Stage2Section(title: 'Pending', children: [
                for (final count in counts)
                  TeamCard(
                    onTap: count.available
                        ? () => _open(count)
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(count.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              if (!count.available)
                                Text('Not available yet',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: p.muted)),
                            ],
                          ),
                        ),
                        Text('${count.count}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
              ]),
              const SizedBox(height: RvmSpacing.lg),
              Stage2Section(title: 'Branch health', children: [
                for (final branch in health.branches)
                  TeamCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(branch.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _stat('Admissions', branch.admissions),
                            _stat('Allotted', branch.joining?.allotted),
                            _stat('Joined', branch.joining?.joined),
                            _stat('Attendance', branch.attendancePct == null
                                ? null
                                : '${branch.attendancePct!.toStringAsFixed(1)}%'),
                            _stat('Dropouts', branch.dropouts),
                            _stat('Overdue', branch.overdueTotal),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (money != null)
                  TeamCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Money (Head of Operations)',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        for (final b in money.branches)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                                '${b.name}: billed ${RvmMoney.fromPaise(b.billedPaise)}, '
                                'collected ${RvmMoney.fromPaise(b.collectedPaise)}, '
                                'outstanding ${RvmMoney.fromPaise(b.outstandingPaise)}'),
                          ),
                        Text('Total collected ${RvmMoney.fromPaise(money.totalCollected)}'),
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

  Widget _stat(String label, Object? value) => Text('$label: ${value ?? '—'}');

  void _open(PendingCount count) {
    switch (count.list) {
      case 'fees_followups':
        context.push('/fees');
      case 'absent_streaks':
        context.push('/ops/absent');
      case 'complaints':
        context.push('/complaints');
      case 'phone_changes':
        context.push('/desk/phone-changes');
      case 'view_requests':
        context.push('/desk/views');
      case 'link_requests':
        context.push('/desk/link');
      case 'placement_verifications':
        context.push('/placement');
      default:
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${count.label} opens on the Scheduler web.')));
    }
  }
}

/// `/ops/absent` — absent on the last three marked classes (#53 item 4).
class AbsentStreaksScreen extends StatefulWidget {
  const AbsentStreaksScreen({super.key});
  @override
  State<AbsentStreaksScreen> createState() => _AbsentStreaksScreenState();
}

class _AbsentStreaksScreenState extends State<AbsentStreaksScreen> {
  Future<List<AbsentStreak>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().absentStreaks());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Absent three in a row')),
      body: FutureBuilder<List<AbsentStreak>>(
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
          if (rows.isEmpty) return stage2Empty('Nobody is on three absences in a row.');
          return ListView.separated(
            padding: const EdgeInsets.all(RvmSpacing.md),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
            itemBuilder: (_, i) {
              final s = rows[i];
              return TeamCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.studentName,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('${s.admissionNumber}${s.batchName == null ? '' : ' · ${s.batchName}'}'),
                    Text('Last absent ${s.lastAbsent ?? '—'}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// `/fees` — the amount-free fees follow-up dialer (#53 items 5–10).
class FeesListScreen extends StatefulWidget {
  const FeesListScreen({super.key});
  @override
  State<FeesListScreen> createState() => _FeesListScreenState();
}

class _FeesListScreenState extends State<FeesListScreen> {
  String _tab = 'today';
  Future<FeeList>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().fees(tab: _tab));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Fees follow-ups'),
        actions: [
          IconButton(
              tooltip: 'Give a colleague access',
              onPressed: _share,
              icon: const Icon(Icons.group_add_outlined)),
          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(RvmSpacing.md),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'today', label: Text('Today')),
                ButtonSegment(value: 'overdue', label: Text('Overdue')),
                ButtonSegment(value: 'upcoming', label: Text('Upcoming')),
              ],
              selected: {_tab},
              onSelectionChanged: (v) {
                _tab = v.first;
                _load();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<FeeList>(
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
                final list = snapshot.data!;
                if (list.rows.isEmpty) {
                  return stage2Empty('No students in $_tab.');
                }
                return RefreshIndicator(
                  color: p.primary,
                  onRefresh: () async => _load(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(RvmSpacing.md),
                    itemCount: list.rows.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: RvmSpacing.sm),
                    itemBuilder: (_, i) {
                      final row = list.rows[i];
                      return TeamCard(
                        onTap: () => context
                            .push('/fees/${row.admissionId}')
                            .then((_) => _load()),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.studentName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                                '${row.admissionNumber} · ${row.courses ?? 'Course'}'
                                '${row.batchName == null ? '' : ' · ${row.batchName}'}'),
                            Text(
                                '${row.daysOverdue} days overdue · ${row.phoneMasked ?? 'number masked'}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: row.daysOverdue > 0
                                            ? p.danger
                                            : p.muted)),
                            if (row.lastRemark != null)
                              Text('“${row.lastRemark}”',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _share() async {
    try {
      final shares = await stage2Repository().feeShares();
      if (!mounted) return;
      final controller = TextEditingController();
      final add = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Give a colleague access'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in shares.mine)
                ListTile(
                    dense: true,
                    title: Text(s.name),
                    trailing: TextButton(
                        onPressed: () async {
                          await stage2Repository().removeFeeShare(s.userId);
                          if (mounted) Navigator.of(context).pop(true);
                        },
                        child: const Text('Stop'))),
              TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                      labelText: 'Staff user id',
                      helperText: 'A portal login of this branch')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Close')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Give access')),
          ],
        ),
      );
      if (add == true && controller.text.trim().isNotEmpty) {
        await stage2Repository().addFeeShare(controller.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('List shared.')));
        }
      }
      controller.dispose();
    } on Failure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }
}

/// `/fees/:id` — one student: history, call and outcome (#53 items 6–9).
class FeeDetailScreen extends StatefulWidget {
  const FeeDetailScreen({super.key, required this.admissionId});
  final String admissionId;
  @override
  State<FeeDetailScreen> createState() => _FeeDetailScreenState();
}

class _FeeDetailScreenState extends State<FeeDetailScreen> {
  Future<List<FeeHistoryRow>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(
      () => _future = stage2Repository().feeHistory(widget.admissionId));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('Student follow-up')),
      body: FutureBuilder<List<FeeHistoryRow>>(
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
          final history = snapshot.data ?? const [];
          return ListView(
            padding: const EdgeInsets.all(RvmSpacing.md),
            children: [
              FilledButton.icon(
                onPressed: _call,
                icon: const Icon(Icons.call_outlined),
                label: const Text('Call the student'),
              ),
              const SizedBox(height: RvmSpacing.sm),
              OutlinedButton.icon(
                onPressed: _outcome,
                icon: const Icon(Icons.edit_note),
                label: const Text('Save an outcome'),
              ),
              const SizedBox(height: RvmSpacing.lg),
              TeamSectionHeader(title: 'History', count: '${history.length}'),
              const SizedBox(height: RvmSpacing.sm),
              if (history.isEmpty) stage2Empty('No follow-up yet.'),
              for (final h in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TeamCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${h.type}${h.outcome == null ? '' : ' · ${h.outcome}'}',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        if (h.remark != null) Text(h.remark!),
                        Text(
                            '${stage2DateTime(h.at)} · ${h.by}'
                            '${h.nextFollowupDate == null ? '' : ' · next ${h.nextFollowupDate}'}',
                            style: Theme.of(context).textTheme.bodySmall),
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

  Future<void> _call() async {
    try {
      final result = await getIt<CallLauncher>().dial(() => stage2Repository()
          .revealFee(widget.admissionId,
              key: 'fee-reveal-${DateTime.now().microsecondsSinceEpoch}'));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    } on Failure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  Future<void> _outcome() async {
    final draft = await showModalBottomSheet<FeeOutcomeDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FeeOutcomeSheet(),
    );
    if (draft == null) return;
    try {
      await stage2Repository().saveFeeOutcome(widget.admissionId, draft,
          key: 'fee-outcome-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Outcome saved.')));
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

class _FeeOutcomeSheet extends StatefulWidget {
  const _FeeOutcomeSheet();
  @override
  State<_FeeOutcomeSheet> createState() => _FeeOutcomeSheetState();
}

class _FeeOutcomeSheetState extends State<_FeeOutcomeSheet> {
  FeeOutcomeDraft _draft = const FeeOutcomeDraft();
  final _remark = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _remark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20,
          MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Outcome', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Answered', label: Text('Answered')),
              ButtonSegment(value: 'No Answer', label: Text('No Answer')),
            ],
            selected: {_draft.status},
            onSelectionChanged: (v) =>
                setState(() => _draft = _draft.copyWith(status: v.first)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remark,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Remark'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined),
            label: Text(_draft.nextDate == null
                ? 'Next follow-up (tomorrow or later)'
                : 'Next follow-up: ${stage2Date(_draft.nextDate)}'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: p.danger)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final draft = _draft.copyWith(remark: _remark.text);
              final problem = draft.validate();
              if (problem != null) {
                setState(() => _error = problem);
                return;
              }
              Navigator.of(context).pop(draft);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final date = await pickStage2Date(
        context, _draft.nextDate ?? tomorrow,
        first: DateTime(tomorrow.year, tomorrow.month, tomorrow.day));
    if (date != null) {
      setState(() => _draft = _draft.copyWith(nextDate: date));
    }
  }
}

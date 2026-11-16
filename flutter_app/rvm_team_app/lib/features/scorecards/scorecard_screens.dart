import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../domain/team_stage2_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import '../stage2/stage2_shared.dart';

String scoreValue(ScoreNumber n) {
  if (!n.available || n.value == null) return '—';
  if (n.unit == 'paise') return RvmMoney.fromPaise(n.value!.toInt());
  if (n.unit == 'percent') return '${n.value!.toStringAsFixed(1)}%';
  return '${n.value}';
}

IconData scoreIcon(String state) => switch (state) {
      'green' => Icons.trending_up,
      'red' => Icons.trending_down,
      _ => Icons.remove,
    };

Color scoreColor(BuildContext context, String state) {
  final p = context.palette;
  return switch (state) {
    'green' => p.success,
    'red' => p.danger,
    _ => p.muted,
  };
}

/// `/scorecards` — the caller's own card (#55). An Admin Manager's money
/// numbers are dropped before they can render (D9).
class ScorecardScreen extends StatefulWidget {
  const ScorecardScreen({super.key});
  @override
  State<ScorecardScreen> createState() => _ScorecardScreenState();
}

class _ScorecardScreenState extends State<ScorecardScreen> {
  Future<Scorecard>? _future;
  String _period = 'week';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(
      () => _future = stage2Repository().myScorecard(period: _period));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Scorecard'),
        actions: [
          IconButton(
              tooltip: 'Targets',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const TargetsScreen())),
              icon: const Icon(Icons.flag_outlined)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(RvmSpacing.md),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'week', label: Text('This week')),
                ButtonSegment(value: 'month', label: Text('This month')),
              ],
              selected: {_period},
              onSelectionChanged: (v) {
                _period = v.first;
                _load();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<Scorecard>(
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
                final card = snapshot.data!.withoutMoneyForAdminManager();
                return _ScoreBody(card: card);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBody extends StatelessWidget {
  const _ScoreBody({required this.card});
  final Scorecard card;

  @override
  Widget build(BuildContext context) {
    if (card.branches.isEmpty) return stage2Empty('No scorecard yet.');
    return ListView(
      padding: const EdgeInsets.all(RvmSpacing.md),
      children: [
        Text('${card.startsOn} to ${card.endsOn}',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: RvmSpacing.md),
        for (final branch in card.branches) ...[
          TeamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(branch.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final n in branch.numbers)
                  _NumberRow(number: n),
              ],
            ),
          ),
          const SizedBox(height: RvmSpacing.sm),
        ],
      ],
    );
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.number});
  final ScoreNumber number;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(number.label,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('How it is calculated: from the Scheduler records for this period.'),
              if (number.target != null)
                Text('Target: ${number.target} (${number.better})'),
              if (number.detail.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${number.detail}'),
              ],
            ],
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(number.label)),
            Text(scoreValue(number),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Icon(scoreIcon(number.state),
                size: 18, color: scoreColor(context, number.state)),
            if (number.target != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text('target ${number.target}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: p.muted)),
              ),
          ],
        ),
      ),
    );
  }
}

/// `/scorecards/branches` — every Admin Manager card side by side (#55).
class BranchScorecardsScreen extends StatefulWidget {
  const BranchScorecardsScreen({super.key});
  @override
  State<BranchScorecardsScreen> createState() => _BranchScorecardsScreenState();
}

class _BranchScorecardsScreenState extends State<BranchScorecardsScreen> {
  Future<Scorecard>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().branchScorecards());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Branch scorecards')),
      body: FutureBuilder<Scorecard>(
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
          final card = snapshot.data!;
          if (card.branches.isEmpty) return stage2Empty('No branch card.');
          final keys = {
            for (final b in card.branches)
              for (final n in b.numbers) n.key,
          }.toList();
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(RvmSpacing.md),
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Number')),
                for (final b in card.branches) DataColumn(label: Text(b.name)),
              ],
              rows: [
                for (final key in keys)
                  DataRow(cells: [
                    DataCell(Text(key.replaceAll('_', ' '))),
                    for (final b in card.branches)
                      DataCell(Text(scoreValue(b.numbers.firstWhere(
                          (n) => n.key == key,
                          orElse: () => ScoreNumber(
                              key: '',
                              value: null,
                              unit: '',
                              target: null,
                              better: '',
                              state: 'none',
                              available: false,
                              detail: {}))))),
                  ]),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// `/scorecards/ceo` — the CEO's card and the HoO's overdue tasks (#55).
class CeoScorecardScreen extends StatefulWidget {
  const CeoScorecardScreen({super.key});
  @override
  State<CeoScorecardScreen> createState() => _CeoScorecardScreenState();
}

class _CeoScorecardScreenState extends State<CeoScorecardScreen> {
  Future<Scorecard>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().ceoScorecard());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('CEO scorecard')),
        body: FutureBuilder<Scorecard>(
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
            return _ScoreBody(card: snapshot.data!);
          },
        ),
      );
}

/// Read-only targets (#55 item 10). Editing stays on the Scheduler web.
class TargetsScreen extends StatefulWidget {
  const TargetsScreen({super.key});
  @override
  State<TargetsScreen> createState() => _TargetsScreenState();
}

class _TargetsScreenState extends State<TargetsScreen> {
  Future<TargetsView>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().targets());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Targets')),
        body: FutureBuilder<TargetsView>(
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
            final view = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(RvmSpacing.md),
              children: [
                Text('Period: ${view.period}',
                    style: Theme.of(context).textTheme.bodySmall),
                for (final t in view.targets)
                  TeamCard(
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(
                                '${t.metricKey.replaceAll('_', ' ')} · branch ${t.locationId}')),
                        Text(t.value == null ? 'no target' : '${t.value}'),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

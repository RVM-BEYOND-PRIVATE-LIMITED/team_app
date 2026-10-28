import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/team_auth_bloc.dart';
import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';

Color _healthColor(BuildContext context, double? pct) {
  if (pct == null) return Theme.of(context).colorScheme.onSurfaceVariant;
  if (pct >= 80) return RvmColors.success;
  if (pct >= 65) return RvmColors.warning;
  return RvmColors.danger;
}

/// The faculty indicators card — month-to-date student attendance across the
/// caller's sessions (`GET /api/attendance/reports/faculty/:id`).
class FacultyIndicatorsScreen extends StatelessWidget {
  const FacultyIndicatorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final facultyId = context.read<TeamAuthBloc>().state.identity?.facultyId;
    if (facultyId == null || facultyId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('My indicators')),
        body: const AppEmpty(
          message:
              'Your login is not linked to a faculty record, so there is no report to show.',
          icon: Icons.insights_outlined,
        ),
      );
    }
    return BlocProvider(
      create: (_) => getIt<FacultyReportBloc>(param1: facultyId)
        ..add(const LoadRequested()),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My indicators'),
          actions: [
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Refresh',
                onPressed: () => context
                    .read<FacultyReportBloc>()
                    .add(const LoadRefreshed()),
                icon: const Icon(Icons.refresh),
              ),
            ),
          ],
        ),
        body: BlocBuilder<FacultyReportBloc, LoadState<FacultyReport>>(
          builder: (context, state) {
            final data = state.data;
            if (state.status == LoadStatus.initial ||
                (state.status == LoadStatus.loading && data == null)) {
              return const AppLoading();
            }
            if (state.status == LoadStatus.failure && data == null) {
              return AppError(
                  message: state.failure?.message ??
                      'Could not load your indicators.',
                  onRetry: () => context
                      .read<FacultyReportBloc>()
                      .add(const LoadRefreshed()));
            }
            return _body(context, data);
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, FacultyReport? report) {
    if (report == null) {
      return const AppEmpty(message: 'No attendance data for this month yet.');
    }
    final scheme = Theme.of(context).colorScheme;
    final pct = report.percentage;
    return RefreshIndicator(
      onRefresh: () async =>
          context.read<FacultyReportBloc>().add(const LoadRefreshed()),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(RvmSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My attendance health',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: RvmSpacing.sm),
                  Text(pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: _healthColor(context, pct),
                                fontWeight: FontWeight.w800,
                              )),
                  const SizedBox(height: 4),
                  Text('Target 80% · month to date',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: RvmSpacing.sm),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: const [
                      _HealthKey(color: RvmColors.success, label: '80%+'),
                      _HealthKey(color: RvmColors.warning, label: '65–79%'),
                      _HealthKey(color: RvmColors.danger, label: 'Below 65%'),
                    ],
                  ),
                  if (report.missingSessions > 0) ...[
                    const SizedBox(height: RvmSpacing.sm),
                    Chip(
                      avatar: const Icon(Icons.error_outline, size: 16),
                      label:
                          Text('${report.missingSessions} sessions not marked'),
                      backgroundColor: scheme.errorContainer,
                      side: BorderSide.none,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: RvmSpacing.md),
          Text('Batches', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: RvmSpacing.xs),
          if (report.batches.isEmpty)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: AppEmpty(message: 'No batches this month.'))
          else
            for (final b in report.batches) _BatchRow(batch: b),
        ],
      ),
    );
  }
}

class _HealthKey extends StatelessWidget {
  const _HealthKey({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.batch});
  final FacultyBatchReport batch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = batch.attendancePercentage;
    return Card(
      // Keep the batch cards apart; the default Card margin is only 4 px and
      // they read as one block on the phone (KP, 26 Oct).
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(batch.batchName,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
                    style: TextStyle(
                        color: _healthColor(context, pct),
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                '${batch.markedSessions}/${batch.expectedSessions} sessions marked · ${batch.studentCount} students',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (!batch.isComplete)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${batch.missingSessions} session(s) missing attendance',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}

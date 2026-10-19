import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/team_auth_bloc.dart';
import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';

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
          message: 'Your login is not linked to a faculty record, so there is no report to show.',
          icon: Icons.insights_outlined,
        ),
      );
    }
    return BlocProvider(
      create: (_) => getIt<FacultyReportBloc>(param1: facultyId)..add(const LoadRequested()),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My indicators'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => context.read<FacultyReportBloc>().add(const LoadRefreshed()),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: BlocBuilder<FacultyReportBloc, LoadState<FacultyReport>>(
          builder: (context, state) {
            return switch (state.status) {
              LoadStatus.loading || LoadStatus.initial => const AppLoading(),
              LoadStatus.failure => AppError(
                  message: state.failure?.message ?? 'Could not load your indicators.',
                  onRetry: () => context.read<FacultyReportBloc>().add(const LoadRefreshed()),
                ),
              _ => _body(context, state.data),
            };
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, FacultyReport? report) {
    if (report == null) return const AppEmpty(message: 'No attendance data for this month yet.');
    final scheme = Theme.of(context).colorScheme;
    final pct = report.percentage;
    return RefreshIndicator(
      onRefresh: () async => context.read<FacultyReportBloc>().add(const LoadRefreshed()),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(RvmSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My attendance health', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: RvmSpacing.sm),
                  Text(pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Target 80% · month to date',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  if (report.missingSessions > 0) ...[
                    const SizedBox(height: RvmSpacing.sm),
                    Chip(
                      avatar: const Icon(Icons.error_outline, size: 16),
                      label: Text('${report.missingSessions} sessions not marked'),
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
            const Padding(padding: EdgeInsets.only(top: 12), child: AppEmpty(message: 'No batches this month.'))
          else
            for (final b in report.batches) _BatchRow(batch: b),
        ],
      ),
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
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(batch.batchName, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
                    style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${batch.markedSessions}/${batch.expectedSessions} sessions marked · ${batch.studentCount} students',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            if (!batch.isComplete)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${batch.missingSessions} session(s) missing attendance',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}

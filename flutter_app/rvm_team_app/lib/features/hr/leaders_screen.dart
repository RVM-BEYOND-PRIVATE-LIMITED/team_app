import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

/// Phase 2D, H5: the leaders' overview — counts only (headcount, today's states, off this week,
/// the approval queue). Backend: `GET /api/ess/leaders/overview` (CEO, super admins).
class LeadersScreen extends StatelessWidget {
  const LeadersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<LoadBloc<LeadersOverview>>()..add(const LoadRequested()),
      child: const _LeadersView(),
    );
  }
}

class _LeadersView extends StatelessWidget {
  const _LeadersView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Leaders',
            subtitle: const Text('Organisation at a glance'),
            actions: [
              Builder(
                builder: (context) => TeamHeaderAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh',
                  onPressed: () => context
                      .read<LoadBloc<LeadersOverview>>()
                      .add(const LoadRefreshed()),
                ),
              ),
            ],
          ),
          Expanded(
            child: BlocBuilder<LoadBloc<LeadersOverview>,
                LoadState<LeadersOverview>>(
              builder: (context, state) {
                if (state.status == LoadStatus.initial ||
                    (state.status == LoadStatus.loading &&
                        state.data == null)) {
                  return const AppLoading();
                }
                if (state.status == LoadStatus.failure && state.data == null) {
                  return AppError(
                    message: state.failure?.message ??
                        'Could not load the overview.',
                    onRetry: () => context
                        .read<LoadBloc<LeadersOverview>>()
                        .add(const LoadRefreshed()),
                  );
                }
                final o = state.data!;
                return RefreshIndicator(
                  onRefresh: () async => context
                      .read<LoadBloc<LeadersOverview>>()
                      .add(const LoadRefreshed()),
                  child: ListView(
                    padding: const EdgeInsets.all(RvmSpacing.md),
                    children: [
                      _Kpi(
                          label: 'Headcount',
                          value: '${o.headcount}',
                          icon: Icons.groups_outlined),
                      const SizedBox(height: RvmSpacing.sm),
                      Wrap(
                        spacing: RvmSpacing.sm,
                        runSpacing: RvmSpacing.sm,
                        children: [
                          _Kpi(
                              label: 'In today',
                              value: '${o.inCount + o.doneCount}',
                              icon: Icons.login,
                              width: 160),
                          _Kpi(
                              label: 'Not in',
                              value: '${o.notIn}',
                              icon: Icons.person_off_outlined,
                              width: 160),
                          _Kpi(
                              label: 'On leave',
                              value: '${o.onLeave}',
                              icon: Icons.beach_access_outlined,
                              width: 160),
                          _Kpi(
                              label: 'Off this week',
                              value: '${o.offThisWeek}',
                              icon: Icons.event_busy_outlined,
                              width: 160),
                        ],
                      ),
                      const SizedBox(height: RvmSpacing.md),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(RvmSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Approval queue',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: RvmSpacing.sm),
                              Text(
                                  '${o.pendingTotal} pending · ${o.pendingAttendance} attendance · ${o.pendingLeave} leave'),
                              if (o.oldestDays != null)
                                Text(
                                    'Oldest waiting ${o.oldestDays} day${o.oldestDays == 1 ? '' : 's'}',
                                    style: const TextStyle(
                                        color: RvmColors.warning)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(
      {required this.label,
      required this.value,
      required this.icon,
      this.width});
  final String label;
  final String value;
  final IconData icon;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(RvmSpacing.md),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: RvmSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    Text(value,
                        style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

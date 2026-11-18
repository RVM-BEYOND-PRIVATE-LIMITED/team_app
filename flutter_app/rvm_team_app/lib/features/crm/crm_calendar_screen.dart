import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/crm_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import 'bloc/crm_blocs.dart';
import 'crm_shared.dart';

/// `/crm/calendar` — this week's follow-ups, grouped by day, overdue in red
/// (team_app #51, item 6). The server sends only the caller's own follow-ups.
class CrmCalendarScreen extends StatelessWidget {
  const CrmCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CrmCalendarBloc(crmRepository())
        ..add(const CrmCalendarLoadRequested()),
      child: const _CrmCalendarView(),
    );
  }
}

class _CrmCalendarView extends StatelessWidget {
  const _CrmCalendarView();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Follow-ups'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => context
                .read<CrmCalendarBloc>()
                .add(const CrmCalendarRefreshed()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: BlocBuilder<CrmCalendarBloc, CrmCalendarState>(
        builder: (context, state) {
          if (state.loading && state.followups.isEmpty) {
            return const AppLoading(label: 'Loading follow-ups…');
          }
          if (state.failure != null && state.followups.isEmpty) {
            return crmFailure(state.failure,
                onRetry: () => context
                    .read<CrmCalendarBloc>()
                    .add(const CrmCalendarRefreshed()));
          }
          if (state.followups.isEmpty) {
            return const AppEmpty(
                message: 'No follow-ups this week.',
                icon: Icons.event_available_outlined);
          }
          final groups = <DateTime, List<CrmFollowup>>{};
          for (final followup in state.followups) {
            final at = followup.at;
            if (at == null) continue;
            final day = DateTime(at.year, at.month, at.day);
            groups.putIfAbsent(day, () => []).add(followup);
          }
          final days = groups.keys.toList()..sort();
          return RefreshIndicator(
            color: p.primary,
            onRefresh: () async => context
                .read<CrmCalendarBloc>()
                .add(const CrmCalendarRefreshed()),
            child: ListView(
              padding: const EdgeInsets.all(RvmSpacing.md),
              children: [
                for (final day in days) ...[
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: RvmSpacing.sm, top: 4),
                    child: Row(
                      children: [
                        Text(
                          '${_weekday(day)} · ${crmDay(day)}',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Text('${groups[day]!.length}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: p.muted)),
                      ],
                    ),
                  ),
                  for (final followup in groups[day]!
                    ..sort((a, b) => (a.at ?? day).compareTo(b.at ?? day)))
                    Padding(
                      padding: const EdgeInsets.only(bottom: RvmSpacing.sm),
                      child: TeamCard(
                        borderColor: followup.overdue ? p.danger : null,
                        onTap: () =>
                            context.push('/crm/lead/${followup.leadId}'),
                        child: Row(
                          children: [
                            Icon(
                              followup.overdue
                                  ? Icons.error_outline
                                  : Icons.schedule,
                              color: followup.overdue ? p.danger : p.primary,
                            ),
                            const SizedBox(width: RvmSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(followup.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${followup.at == null ? '' : crmTime(followup.at!)} · '
                                    '${followup.phoneMasked} · ${followup.stage}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            fontSize: 11.5,
                                            color: followup.overdue
                                                ? p.danger
                                                : p.muted),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: RvmSpacing.sm),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  static String _weekday(DateTime day) => switch (day.weekday) {
        DateTime.monday => 'Monday',
        DateTime.tuesday => 'Tuesday',
        DateTime.wednesday => 'Wednesday',
        DateTime.thursday => 'Thursday',
        DateTime.friday => 'Friday',
        DateTime.saturday => 'Saturday',
        _ => 'Sunday',
      };
}

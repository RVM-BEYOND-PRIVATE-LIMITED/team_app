import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import '../../widgets/team_kit.dart';

class FacultyAttendanceInbox extends StatelessWidget {
  const FacultyAttendanceInbox({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<LoadBloc<FacultyDay>>()..add(const LoadRequested()),
      child: Scaffold(
        backgroundColor: RvmColors.ivory,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            TeamCollapsingHeader(
              contentHeight: 124,
              title: 'Mark attendance',
              actions: [
                Builder(
                  builder: (context) => TeamHeaderAction(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh',
                    onPressed: () => context
                        .read<LoadBloc<FacultyDay>>()
                        .add(const LoadRefreshed()),
                  ),
                ),
              ],
              expanded: TeamPageHeader(
                title: 'Mark attendance',
                eyebrow: 'Faculty',
                subtitle: const Text("Today's batches and student attendance"),
                actions: [
                  const TeamBrandMark(),
                  Builder(
                    builder: (context) => TeamHeaderAction(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Refresh',
                      onPressed: () => context
                          .read<LoadBloc<FacultyDay>>()
                          .add(const LoadRefreshed()),
                    ),
                  ),
                ],
              ),
            ),
          ],
          body: BlocBuilder<LoadBloc<FacultyDay>, LoadState<FacultyDay>>(
            builder: (context, state) {
              final day = state.data;
              if (state.status == LoadStatus.initial ||
                  (state.status == LoadStatus.loading && day == null)) {
                return const AppLoading(label: 'Loading your batches');
              }
              if (state.status == LoadStatus.failure && day == null) {
                return AppError(
                  message:
                      state.failure?.message ?? 'Could not load your batches.',
                  onRetry: () => context
                      .read<LoadBloc<FacultyDay>>()
                      .add(const LoadRefreshed()),
                );
              }
              return _body(context, day);
            },
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, FacultyDay? day) {
    if (day == null) {
      return const AppEmpty(message: 'No batches to mark today.');
    }
    final sessions = day.sessions;
    return RefreshIndicator(
      onRefresh: () async =>
          context.read<LoadBloc<FacultyDay>>().add(const LoadRefreshed()),
      child: ListView(
        padding: const EdgeInsets.all(RvmSpacing.md),
        children: [
          TeamCard(
            child: Row(
              children: [
                const TeamIconBadge(
                    icon: Icons.fact_check_outlined, size: 38, iconSize: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${day.markedToday} of ${day.sessionsToday} marked today',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontSize: 13)),
                      Text(
                          'This month ${day.monthPercentage}% · ${day.activeStudents} active students',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 10.5)),
                    ],
                  ),
                ),
                TeamPill(
                  label: day.pendingRemarks > 0
                      ? '${day.pendingRemarks} remarks due'
                      : 'On track',
                  tone: day.pendingRemarks > 0
                      ? TeamPillTone.warning
                      : TeamPillTone.success,
                  dense: true,
                ),
              ],
            ),
          ),
          if (sessions.isNotEmpty) ...[
            const SizedBox(height: RvmSpacing.md),
            TeamSectionHeader(
              title: "Today's batches",
              titleStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
              trailing: TextButton(
                onPressed: () => context.push('/work/batches'),
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28), padding: EdgeInsets.zero),
                child:
                    const Text('All batches', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(height: 8),
            for (final session in sessions) ...[
              _SessionCard(session: session),
              const SizedBox(height: 8),
            ],
          ] else ...[
            const SizedBox(height: RvmSpacing.lg),
            const AppEmpty(
              icon: Icons.event_available_outlined,
              message: 'No classes are scheduled for today.',
            ),
            const SizedBox(height: RvmSpacing.md),
            OutlinedButton.icon(
              onPressed: () => context.push('/work/batches'),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('Open all my batches'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});
  final FacultySession session;

  @override
  Widget build(BuildContext context) {
    final time = [
      if (session.startTime != null)
        '${session.startTime}${session.endTime != null ? '–${session.endTime}' : ''}',
      if (session.locationName != null) session.locationName!,
      '${session.students} students',
    ].join(' · ');
    return TeamCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      onTap: () => _open(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.name.replaceAll('_', ' '),
                  softWrap: true,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  softWrap: true,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (session.covered)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: TeamPill(
                  label: 'Covered', tone: TeamPillTone.info, dense: true),
            ),
          TeamPill(
            label: session.marked ? 'Marked' : 'Mark',
            tone: session.marked ? TeamPillTone.success : TeamPillTone.orange,
            dense: true,
          ),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: RvmColors.subtle),
        ],
      ),
    );
  }

  void _open(BuildContext context) {
    context.push('/work/batch/${session.id}/mark', extra: session.name);
  }
}

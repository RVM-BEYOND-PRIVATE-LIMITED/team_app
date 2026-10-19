import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/team_permissions.dart';
import '../../bloc/team_auth_bloc.dart';
import '../../domain/ess_models.dart';
import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: BlocBuilder<TeamAuthBloc, TeamAuthState>(
              builder: (context, auth) {
                final identity = auth.identity;
                final perms = TeamPermissions.forRole(identity?.role ?? AppRole.unknown);
                return RefreshIndicator(
                  onRefresh: () async {},
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _HomeHeader(identity: identity),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, RvmSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _OffThisWeekCard(),
                            const SizedBox(height: RvmSpacing.md),
                            if (perms.canSeeFacultyWork) ...[
                              _FacultyCard(),
                              const SizedBox(height: RvmSpacing.md),
                            ],
                            if (perms.canSeeHodWork) ...[
                              _HodCard(),
                              const SizedBox(height: RvmSpacing.md),
                            ],
                            if (perms.canSeePriorityTasks) ...[
                              _PrioritySummaryCard(),
                              const SizedBox(height: RvmSpacing.md),
                            ],
                            _InterviewsCard(perms: perms),
                            const SizedBox(height: RvmSpacing.md),
                            _QuickActionsCard(perms: perms),
                            const SizedBox(height: RvmSpacing.md),
                            _AnnouncementsSection(),
                          ],
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

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.identity});
  final StaffIdentity? identity;

  @override
  Widget build(BuildContext context) {
    final name = identity?.username ?? 'Welcome';
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
    final role = (appRoleWire(identity?.role ?? AppRole.unknown) ?? '—').toUpperCase();
    final location = identity?.locationName;

    return TeamPageHeader(
      eyebrow: _greeting(DateTime.now().hour),
      title: name,
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: RvmColors.ivory,
        child: Text(
          initial,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: RvmColors.ironwood, fontWeight: FontWeight.w700),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => context.push('/notifications'),
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
      footer: Row(
        children: [
          TeamHeaderPill(label: role),
          if (location != null && location.isNotEmpty) ...[
            const SizedBox(width: RvmSpacing.sm),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 14, color: RvmColors.ivory.withValues(alpha: 0.85)),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: RvmColors.ivory.withValues(alpha: 0.9)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _greeting(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class _OffThisWeekCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<LoadBloc<TeamOffWeek>>()..add(const LoadRequested()),
      child: BlocBuilder<LoadBloc<TeamOffWeek>, LoadState<TeamOffWeek>>(
        builder: (context, state) {
          if (state.status == LoadStatus.loading || state.status == LoadStatus.initial) {
            return _SectionCard(
              title: 'Off this week',
              child: const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          if (state.status == LoadStatus.failure) return const SizedBox.shrink();
          final data = state.data;
          if (data == null || data.scope == null || data.people.isEmpty) {
            return _SectionCard(title: 'Off this week', child: const Text('Nobody is off this week.'));
          }
          return _SectionCard(
            title: 'Off this week',
            trailing: TextButton(onPressed: () => context.push('/team/directory'), child: const Text('Directory')),
            child: Column(
              children: [
                for (final p in data.people)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(p.card.fullName.trim().isEmpty
                          ? '?'
                          : p.card.fullName.trim().substring(0, 1).toUpperCase()),
                    ),
                    title: Text(p.card.fullName),
                    subtitle: Text(p.days.join(', ')),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: RvmSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

class _FacultyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: "Today's classes",
      trailing: TextButton(onPressed: () => context.push('/work/batches'), child: const Text('My batches')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Open your batches to mark today’s student attendance.'),
          const SizedBox(height: RvmSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => context.push('/work/indicators'),
            icon: const Icon(Icons.insights_outlined, size: 18),
            label: const Text('My attendance health'),
          ),
        ],
      ),
    );
  }
}

class _HodCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Faculty Development',
      trailing: TextButton(onPressed: () => context.push('/work/hod'), child: const Text('Open')),
      child: const Text('Your team to-do list, interview verdicts, risk logs and day comments.'),
    );
  }
}

class _PrioritySummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<InboxBloc>()..add(const LoadRequested()),
      child: BlocBuilder<InboxBloc, LoadState<PriorityInbox>>(
        builder: (context, state) {
          return _SectionCard(
            title: 'Priority tasks',
            child: switch (state.status) {
              LoadStatus.loading || LoadStatus.initial =>
                const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              LoadStatus.failure => Text(state.failure?.message ?? 'Could not load tasks.'),
              LoadStatus.empty => const Text('Nothing on your plate right now.'),
              LoadStatus.success => Row(
                  children: [
                    Text('${state.data!.outstanding}', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(width: 8),
                    Text('outstanding · ${state.data!.unread} unread'),
                  ],
                ),
            },
          );
        },
      ),
    );
  }
}

class _InterviewsCard extends StatelessWidget {
  const _InterviewsCard({required this.perms});
  final TeamPermissions perms;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<InterviewsBloc>()..add(const LoadRequested()),
      child: BlocBuilder<InterviewsBloc, LoadState<List<InterviewRound>>>(
        builder: (context, state) {
          if (state.status == LoadStatus.failure || state.status == LoadStatus.empty) {
            return const SizedBox.shrink();
          }
          final round = (state.data ?? const <InterviewRound>[]).isNotEmpty ? state.data!.first : null;
          if (round == null) return const SizedBox.shrink();
          return _SectionCard(
            title: 'Next interview (24h)',
            trailing: TextButton(onPressed: () => context.push('/work/interviews'), child: const Text('All')),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(round.candidateName ?? 'Candidate', style: Theme.of(context).textTheme.bodyLarge),
                if (round.position != null) Text(round.position!, style: Theme.of(context).textTheme.bodySmall),
                if (round.scheduledAt != null)
                  Text('At ${TimeOfDay.fromDateTime(round.scheduledAt!.toLocal()).format(context)}',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({required this.perms});
  final TeamPermissions perms;

  @override
  Widget build(BuildContext context) {
    // (icon, label, route) — a null route is a feature the backend does not
    // expose yet (work-from-home, 2B helpdesk raise).
    final caps = context.watch<CapabilitiesBloc>().state.data;
    final actions = <(IconData, String, String?)>[
      (Icons.fingerprint, 'Punch in / out', '/me/punch'),
      (Icons.today_outlined, 'My day', '/me/attendance'),
      (Icons.event_note_outlined, 'Requests & leave', '/requests'),
      if (caps?.approvalsOwnReports == true || caps?.approvalsAnyRequest == true)
        (Icons.fact_check_outlined, 'Approvals', '/approvals'),
      (Icons.work_off_outlined, 'Work from home', null),
    ];
    return _SectionCard(
      title: 'Quick actions',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in actions)
            ActionChip(
              avatar: Icon(a.$1, size: 18),
              label: Text(a.$2),
              onPressed: () => a.$3 != null ? context.push(a.$3!) : _pending(context, a.$2),
            ),
        ],
      ),
    );
  }

  void _pending(BuildContext context, String name) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$name needs the new backend — not available yet.')));
  }
}

class _AnnouncementsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<HomeAnnouncementsBloc>()..add(const LoadRequested()),
      child: BlocBuilder<HomeAnnouncementsBloc, LoadState<List<TeamAnnouncement>>>(
        builder: (context, state) {
          return _SectionCard(
            title: 'Announcements',
            child: switch (state.status) {
              LoadStatus.loading || LoadStatus.initial =>
                const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              LoadStatus.failure => Text(state.failure?.message ?? 'Could not load announcements.'),
              LoadStatus.empty => const Text('No announcements right now.'),
              LoadStatus.success => Column(
                  children: [
                    for (final a in state.data!.take(5))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(a.title),
                        subtitle: Text(a.message, maxLines: 2, overflow: TextOverflow.ellipsis),
                        leading: const Icon(Icons.campaign_outlined),
                      ),
                  ],
                ),
            },
          );
        },
      ),
    );
  }
}

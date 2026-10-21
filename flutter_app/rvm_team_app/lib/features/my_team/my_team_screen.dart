import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/team_header.dart';
import 'bloc/team_today_bloc.dart';

/// E6/H4: Team today, off this week, the reporting chain, peers, reports, department, and the
/// colleague directory (E2/E8/E11). Backend: `/api/ess/team/*`, `/api/ess/me/org`,
/// `/api/ess/directory` (Phase 1E, live).
class MyTeamScreen extends StatelessWidget {
  const MyTeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
            create: (_) =>
                getIt<TeamTodayBloc>()..add(const TeamTodayLoadRequested())),
        BlocProvider(
            create: (_) =>
                getIt<LoadBloc<OrgView>>()..add(const LoadRequested())),
        BlocProvider(
            create: (_) =>
                getIt<LoadBloc<TeamOffWeek>>()..add(const LoadRequested())),
      ],
      child: Scaffold(
        body: Column(
          children: [
            TeamPageHeader(
              title: 'My Team',
              subtitle: const Text('Your manager, peers and reporting chain'),
              actions: [
                Builder(
                  builder: (context) => TeamHeaderAction(
                    icon: Icons.search_rounded,
                    tooltip: 'Search colleagues',
                    onPressed: () => context.push('/team/directory'),
                  ),
                ),
              ],
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  context
                      .read<TeamTodayBloc>()
                      .add(const TeamTodayLoadRequested());
                  context.read<LoadBloc<OrgView>>().add(const LoadRefreshed());
                  context
                      .read<LoadBloc<TeamOffWeek>>()
                      .add(const LoadRefreshed());
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(RvmSpacing.md,
                      RvmSpacing.md, RvmSpacing.md, RvmSpacing.lg),
                  children: const [
                    _TeamTodayCard(),
                    SizedBox(height: RvmSpacing.md),
                    _OffThisWeekCard(),
                    SizedBox(height: RvmSpacing.md),
                    _OrgCardSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamTodayCard extends StatelessWidget {
  const _TeamTodayCard();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Team today',
      child: BlocBuilder<TeamTodayBloc, TeamTodayState>(
        builder: (context, state) {
          if (state.status == LoadStatus.loading ||
              state.status == LoadStatus.initial) {
            return const SizedBox(
                height: 48,
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2)));
          }
          if (state.status == LoadStatus.failure) {
            return Text(state.failure?.message ?? 'Could not load your team.');
          }
          final data = state.data!;
          if (!data.hasRoster) {
            return const Text(
                'No direct reports or branch roster for your login.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  _FilterChip(
                      label: 'All ${data.all}',
                      selected: state.filter == 'all',
                      value: 'all'),
                  _FilterChip(
                      label: 'Not in ${data.notIn}',
                      selected: state.filter == 'not_in',
                      value: 'not_in'),
                  _FilterChip(
                      label: 'Late ${data.late}',
                      selected: state.filter == 'late',
                      value: 'late'),
                  _FilterChip(
                      label: 'On leave ${data.onLeave}',
                      selected: state.filter == 'on_leave',
                      value: 'on_leave'),
                ],
              ),
              const SizedBox(height: RvmSpacing.sm),
              if (data.people.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Nobody in this filter.'))
              else
                for (final p in data.people) _TeamRow(person: p),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.value});
  final String label;
  final bool selected;
  final String value;
  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) =>
            context.read<TeamTodayBloc>().add(TeamTodayFiltered(value)),
      );
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.person});
  final TeamPerson person;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (person.state) {
      'in' => ('In', RvmColors.success),
      'done' => ('Done', scheme.primary),
      'on_leave' => ('On leave', RvmColors.warning),
      'week_off' => ('Week off', scheme.onSurfaceVariant),
      'holiday' => ('Holiday', scheme.onSurfaceVariant),
      _ => ('Not in', RvmColors.danger),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _Avatar(name: person.card.fullName),
      title: Text(person.card.fullName),
      subtitle: Text([person.card.designation, person.card.department?.name]
          .where((s) => s != null && s.isNotEmpty)
          .join(' · ')),
      trailing: person.late
          ? Text('Late',
              style: TextStyle(
                  color: RvmColors.danger, fontWeight: FontWeight.w600))
          : _Chip(label: label, color: color),
    );
  }
}

class _OffThisWeekCard extends StatelessWidget {
  const _OffThisWeekCard();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Off this week',
      child: BlocBuilder<LoadBloc<TeamOffWeek>, LoadState<TeamOffWeek>>(
        builder: (context, state) {
          if (state.status == LoadStatus.loading ||
              state.status == LoadStatus.initial) {
            return const SizedBox(
                height: 40,
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2)));
          }
          if (state.status == LoadStatus.failure) {
            return Text(state.failure?.message ?? 'Could not load.');
          }
          final data = state.data;
          if (data == null || data.scope == null || data.people.isEmpty) {
            return const Text('Nobody is on leave this week.');
          }
          return Column(
            children: [
              for (final p in data.people)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _Avatar(name: p.card.fullName),
                  title: Text(p.card.fullName),
                  subtitle: Text(p.days.join(', ')),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OrgCardSection extends StatelessWidget {
  const _OrgCardSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoadBloc<OrgView>, LoadState<OrgView>>(
      builder: (context, state) {
        if (state.status == LoadStatus.loading ||
            state.status == LoadStatus.initial) {
          return const _Panel(
              title: 'Reporting chain',
              child: SizedBox(
                  height: 40,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2))));
        }
        if (state.status == LoadStatus.failure) {
          return _Panel(
              title: 'Reporting chain',
              child: Text(state.failure?.message ?? 'Could not load.'));
        }
        final org = state.data!;
        return Column(
          children: [
            _Panel(
              title: 'Reporting chain',
              child: org.managerChain.isEmpty
                  ? const Text('No manager recorded.')
                  : Column(children: [
                      for (final m in org.managerChain) _PersonTile(card: m)
                    ]),
            ),
            if (org.peers.isNotEmpty) ...[
              const SizedBox(height: RvmSpacing.md),
              _Panel(
                  title: 'Peers',
                  child: Column(children: [
                    for (final p in org.peers) _PersonTile(card: p)
                  ])),
            ],
            if (org.directReports.isNotEmpty) ...[
              const SizedBox(height: RvmSpacing.md),
              _Panel(
                  title: 'My reports (${org.directReportCount})',
                  child: Column(children: [
                    for (final p in org.directReports) _PersonTile(card: p)
                  ])),
            ],
            if (org.department != null) ...[
              const SizedBox(height: RvmSpacing.md),
              _Panel(
                  title: org.department!.name,
                  child: Column(children: [
                    for (final p in org.departmentPeople) _PersonTile(card: p)
                  ])),
            ],
          ],
        );
      },
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.card});
  final OrgCard card;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _Avatar(name: card.fullName),
      title: Row(
        children: [
          Flexible(child: Text(card.fullName, overflow: TextOverflow.ellipsis)),
          if (card.noticePeriod) ...[
            const SizedBox(width: 6),
            const _Chip(label: 'Notice period', color: RvmColors.warning),
          ],
        ],
      ),
      subtitle: Text([card.designation, card.email, card.phone]
          .where((s) => s != null && s.isNotEmpty)
          .join(' · ')),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final s = name.trim();
    return CircleAvatar(
        child: Text(s.isEmpty ? '?' : s.substring(0, 1).toUpperCase()));
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      );
}

/// A titled card panel used across this screen (and the directory).
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: RvmSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

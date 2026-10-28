import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/team_header.dart';
import 'bloc/team_today_bloc.dart';
import 'colleague_profile_sheet.dart';

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
      child: Builder(
        builder: (context) => Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              TeamCollapsingHeader(
                contentHeight: 116,
                title: 'My Team',
                actions: [
                  Builder(
                    builder: (context) => TeamHeaderAction(
                      icon: Icons.search_rounded,
                      tooltip: 'Search colleagues',
                      onPressed: () => context.push('/team/directory'),
                    ),
                  ),
                ],
                expanded: TeamPageHeader(
                  title: 'My Team',
                  subtitle: const Text('Reporting chain'),
                  actions: [
                    const TeamBrandMark(),
                    Builder(
                      builder: (context) => TeamHeaderAction(
                        icon: Icons.search_rounded,
                        tooltip: 'Search colleagues',
                        onPressed: () => context.push('/team/directory'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            body: RefreshIndicator(
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
                padding: const EdgeInsets.fromLTRB(
                    RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, RvmSpacing.lg),
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
      onTap: () => showColleagueProfile(context, person.card),
      leading: _Avatar(name: person.card.fullName),
      title: Text(person.card.fullName),
      subtitle: Text(person.card.designation ?? 'Job role not recorded'),
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
                  onTap: () => showColleagueProfile(context, p.card),
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
              title: 'Hierarchy',
              child: SizedBox(
                  height: 40,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2))));
        }
        if (state.status == LoadStatus.failure) {
          return _Panel(
              title: 'Hierarchy',
              child: Text(state.failure?.message ?? 'Could not load.'));
        }
        final org = state.data!;
        if (org.tree.isNotEmpty) {
          return _Panel(title: 'Hierarchy', child: _OrgTree(roots: org.tree));
        }
        if (org.managerChain.isNotEmpty) {
          return _Panel(
              title: 'Hierarchy',
              child: _ReportingTree(chain: org.managerChain));
        }
        return const _Panel(
            title: 'Hierarchy',
            child: Text('No reporting hierarchy is recorded for your login.'));
      },
    );
  }
}

class _OrgTree extends StatefulWidget {
  const _OrgTree({required this.roots});
  final List<OrgNode> roots;

  @override
  State<_OrgTree> createState() => _OrgTreeState();
}

class _OrgTreeState extends State<_OrgTree> {
  final Set<String> _collapsed = {};

  Iterable<String> _allIds(List<OrgNode> nodes) sync* {
    for (final node in nodes) {
      yield node.card.id;
      yield* _allIds(node.children);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allOpen = _collapsed.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() {
              if (allOpen) {
                _collapsed.addAll(_allIds(widget.roots));
              } else {
                _collapsed.clear();
              }
            }),
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 28), padding: EdgeInsets.zero),
            child: Text(allOpen ? 'Collapse all' : 'Expand all',
                style: const TextStyle(fontSize: 11)),
          ),
        ),
        for (final root in widget.roots) _node(root),
      ],
    );
  }

  Widget _node(OrgNode node) {
    final hasChildren = node.children.isNotEmpty;
    final expanded = !_collapsed.contains(node.card.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PersonRow(
          card: node.card,
          isMe: node.isMe,
          trailing: hasChildren
              ? IconButton(
                  tooltip: expanded ? 'Collapse' : 'Expand',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    final id = node.card.id;
                    if (!_collapsed.remove(id)) _collapsed.add(id);
                  }),
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: RvmColors.subtle,
                  ),
                )
              : null,
        ),
        if (hasChildren && expanded)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 1.2),
                ),
              ),
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final child in node.children) _node(child),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Fallback when the backend cannot yet send the full tree: the upward
/// reporting chain, top-down, with the viewer at the bottom.
class _ReportingTree extends StatefulWidget {
  const _ReportingTree({required this.chain});
  final List<OrgCard> chain;

  @override
  State<_ReportingTree> createState() => _ReportingTreeState();
}

class _ReportingTreeState extends State<_ReportingTree> {
  final Set<String> _collapsed = {};

  bool _visible(int index, List<OrgCard> topDown) {
    for (var i = 0; i < index; i++) {
      if (_collapsed.contains(topDown[i].id)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final topDown = widget.chain.reversed.toList(growable: false);
    final allOpen = _collapsed.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() {
              if (allOpen) {
                _collapsed.addAll(topDown.map((p) => p.id));
              } else {
                _collapsed.clear();
              }
            }),
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 28), padding: EdgeInsets.zero),
            child: Text(allOpen ? 'Collapse all' : 'Expand all',
                style: const TextStyle(fontSize: 11)),
          ),
        ),
        for (var i = 0; i < topDown.length; i++)
          if (_visible(i, topDown))
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
              child: _PersonRow(
                card: topDown[i],
                trailing: i < topDown.length - 1
                    ? IconButton(
                        tooltip: _collapsed.contains(topDown[i].id)
                            ? 'Expand'
                            : 'Collapse',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          final id = topDown[i].id;
                          if (!_collapsed.remove(id)) _collapsed.add(id);
                        }),
                        icon: Icon(
                          _collapsed.contains(topDown[i].id)
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_up_rounded,
                          size: 20,
                          color: RvmColors.subtle,
                        ),
                      )
                    : null,
              ),
            ),
        if (_visible(topDown.length, topDown))
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => context.push('/me/profile'),
              leading: const CircleAvatar(child: Text('·')),
              title: const Text('You'),
              subtitle: const Text('Your position in this chain'),
            ),
          ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.card, this.trailing, this.isMe = false});
  final OrgCard card;
  final Widget? trailing;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => showColleagueProfile(context, card),
      borderRadius: BorderRadius.circular(RvmRadii.sm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
        child: Row(
          children: [
            _Avatar(name: card.fullName, size: 30),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          card.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                              fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        const _Chip(
                            label: 'You',
                            color: RvmColors.teamSeed,
                            dense: true),
                      ],
                      if (card.noticePeriod) ...[
                        const SizedBox(width: 4),
                        const _Chip(
                            label: 'Notice',
                            color: RvmColors.warning,
                            dense: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    card.designation ?? 'Job role not recorded',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                        fontSize: 10.5, height: 1.2, color: RvmColors.muted),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              SizedBox(
                width: 32,
                height: 32,
                child: trailing,
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 40});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final s = name.trim();
    return CircleAvatar(
      radius: size / 2,
      child: Text(
        s.isEmpty ? '?' : s.substring(0, 1).toUpperCase(),
        style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.dense = false});
  final String label;
  final Color color;
  final bool dense;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: dense ? 5 : 8, vertical: dense ? 1.5 : 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontSize: dense ? 8.5 : null,
                fontWeight: FontWeight.w600)),
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

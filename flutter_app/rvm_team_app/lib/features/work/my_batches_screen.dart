import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';

/// The batches the signed-in faculty/HOD teaches (`GET /api/batches` — the
/// server already filters to the caller's own batches).
///
/// Layout follows `issues_image/design1.png`: light header with the instructor
/// subtitle, a rounded search bar with a sort control, status pills with
/// counts, and a compact card per batch showing the skill, batch code, name,
/// student count, class roll, timings, days, dates, faculty and the logs link.
/// No floating action button.
class MyBatchesScreen extends StatelessWidget {
  const MyBatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RvmColors.ivory,
      body: SafeArea(
        bottom: false,
        child: BlocProvider(
          create: (_) => getIt<MyBatchesBloc>()..add(const LoadRequested()),
          child: const _BatchesView(),
        ),
      ),
    );
  }
}

enum _Sort { newest, name, status }

class _BatchesView extends StatefulWidget {
  const _BatchesView();

  @override
  State<_BatchesView> createState() => _BatchesViewState();
}

class _BatchesViewState extends State<_BatchesView> {
  static const _statuses = ['all', 'active', 'upcoming', 'completed'];
  String _status = 'all';
  _Sort _sort = _Sort.newest;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, int> _counts(List<TeamBatch> all) {
    int of(String s) => s == 'all'
        ? all.length
        : all.where((b) => (b.status ?? 'active').toLowerCase() == s).length;
    return {
      for (final s in _statuses) s: of(s),
    };
  }

  List<TeamBatch> _filtered(List<TeamBatch> all) {
    final q = _search.text.trim().toLowerCase();
    final shown = all.where((b) {
      if (_status != 'all' &&
          (b.status ?? 'active').toLowerCase() != _status) {
        return false;
      }
      if (q.isEmpty) return true;
      return b.name.toLowerCase().contains(q) ||
          (b.skillName?.toLowerCase().contains(q) ?? false) ||
          (b.facultyName?.toLowerCase().contains(q) ?? false);
    }).toList();

    switch (_sort) {
      case _Sort.newest:
        shown.sort((a, b) => (b.startDate ?? '').compareTo(a.startDate ?? ''));
      case _Sort.name:
        shown.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _Sort.status:
        const order = {'active': 0, 'upcoming': 1, 'completed': 2};
        shown.sort((a, b) => (order[(a.status ?? 'active').toLowerCase()] ?? 3)
            .compareTo(order[(b.status ?? 'active').toLowerCase()] ?? 3));
    }
    return shown;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MyBatchesBloc, LoadState<List<TeamBatch>>>(
      builder: (context, state) {
        final data = state.data;
        if (state.status == LoadStatus.initial ||
            (state.status == LoadStatus.loading && data == null)) {
          return const AppLoading();
        }
        if (state.status == LoadStatus.failure && data == null) {
          return AppError(
            message: state.failure?.message ?? 'Could not load your batches.',
            onRetry: () =>
                context.read<MyBatchesBloc>().add(const LoadRefreshed()),
          );
        }
        final batches = data ?? const <TeamBatch>[];
        final counts = _counts(batches);
        final shown = _filtered(batches);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              onRefresh: () =>
                  context.read<MyBatchesBloc>().add(const LoadRefreshed()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _SearchField(
                controller: _search,
                sort: _sort,
                onQuery: () => setState(() {}),
                onSort: (s) => setState(() => _sort = s),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final s in _statuses)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _StatusPill(
                        label: _statusLabel(s),
                        count: counts[s] ?? 0,
                        selected: _status == s,
                        onTap: () => setState(() => _status = s),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async =>
                    context.read<MyBatchesBloc>().add(const LoadRefreshed()),
                child: shown.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: const [
                          AppEmpty(
                            message: 'No batches match this filter.',
                            icon: Icons.filter_list_off_outlined,
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, i) =>
                            _BatchCard(batch: shown[i]),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'all' => 'All',
        'active' => 'Active',
        'upcoming' => 'Upcoming',
        _ => 'Completed',
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          InkWell(
            onTap: () => context.pop(),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                  color: RvmColors.white, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 16, color: RvmColors.ink),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My batches',
                    style: text.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700, fontSize: 20)),
                const SizedBox(height: 1),
                Text('Instructor portal & schedules',
                    style: text.bodySmall
                        ?.copyWith(fontSize: 11, color: RvmColors.muted)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: RvmColors.ink),
            onSelected: (_) => onRefresh(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('Refresh')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.sort,
    required this.onQuery,
    required this.onSort,
  });
  final TextEditingController controller;
  final _Sort sort;
  final VoidCallback onQuery;
  final ValueChanged<_Sort> onSort;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: RvmColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RvmColors.line),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Icon(Icons.search_rounded,
                size: 18, color: RvmColors.subtle),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onQuery(),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search batch, skill or faculty',
                hintStyle: TextStyle(fontSize: 13, color: RvmColors.subtle),
                // The app theme draws an OutlineInputBorder for every field;
                // this one is already inside the rounded white container, so
                // all three must be cleared or a second box shows inside.
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 13),
              ),
            ),
          ),
          PopupMenuButton<_Sort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.tune_rounded,
                size: 18, color: RvmColors.ink),
            onSelected: onSort,
            itemBuilder: (_) => [
              _sortItem(_Sort.newest, 'Newest first', sort),
              _sortItem(_Sort.name, 'Name (A–Z)', sort),
              _sortItem(_Sort.status, 'Status', sort),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_Sort> _sortItem(_Sort value, String label, _Sort current) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(
              current == value
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 16,
              color: current == value ? RvmColors.clay : RvmColors.subtle,
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? RvmColors.brand : RvmColors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? RvmColors.brand : RvmColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: selected ? RvmColors.ivory : RvmColors.ink,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected
                    ? RvmColors.ivory.withValues(alpha: 0.75)
                    : RvmColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.batch});
  final TeamBatch batch;

  /// `HH:MM:SS` → `HH:MM`; anything else passes through untouched.
  static String _hhmm(String? t) {
    if (t == null || t.isEmpty) return '';
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(t.trim());
    return m == null ? t : '${m[1]!.padLeft(2, '0')}:${m[2]}';
  }

  static String _shortDays(List<String> days) => days
      .map((d) => d.trim())
      .where((d) => d.isNotEmpty)
      .map((d) => d.length <= 3 ? d : d.substring(0, 3))
      .join(', ');

  /// `2026-05-18` → `2026-05-18`; a timestamp is cut to its day.
  static String _day(String? value) {
    if (value == null || value.isEmpty) return '';
    return value.length >= 10 ? value.substring(0, 10) : value;
  }

  /// `batches` has no code column, so the card shows a short form of its id.
  String get _code {
    final hex = batch.id.replaceAll('-', '');
    if (hex.isEmpty) return '';
    return '#BATCH-${hex.substring(0, hex.length < 4 ? hex.length : 4).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = (batch.status ?? 'active').toLowerCase();
    final time = [_hhmm(batch.startTime), _hhmm(batch.endTime)]
        .where((t) => t.isNotEmpty)
        .join(' – ');
    final days = _shortDays(batch.daysOfWeek);
    final from = _day(batch.startDate);
    final to = _day(batch.endDate);
    final dates = [from, to].where((d) => d.isNotEmpty).join(' → ');
    final roll =
        batch.scheduleDays.isEmpty ? const <int>[] : batch.scheduleDays;

    return Material(
      color: RvmColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/work/batch/${batch.id}/mark',
            extra: batch.name),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: RvmColors.line),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 13, color: RvmColors.clay),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      (batch.skillName ?? 'Batch').toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(
                        fontSize: 10.5,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w800,
                        color: RvmColors.clay,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_code.isNotEmpty)
                    Text(_code,
                        style: text.labelSmall?.copyWith(
                            fontSize: 9.5, color: RvmColors.subtle)),
                  const Spacer(),
                  _StatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                batch.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(
                    fontSize: 14.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              // Wrap, not Row: on a 320px phone the student count plus six
              // roll chips is wider than the card.
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.groups_2_outlined,
                          size: 13, color: RvmColors.muted),
                      const SizedBox(width: 4),
                      Text('${batch.joinedCount}/${batch.students} students',
                          style: text.bodySmall
                              ?.copyWith(fontSize: 11, color: RvmColors.ink)),
                    ],
                  ),
                  if (roll.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Class roll:',
                            style: text.bodySmall?.copyWith(
                                fontSize: 10, color: RvmColors.muted)),
                        const SizedBox(width: 5),
                        for (final n in roll.take(6)) _RollChip(number: n),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      size: 13, color: RvmColors.muted),
                  const SizedBox(width: 4),
                  Text(time.isEmpty ? '—' : time,
                      style: text.bodySmall
                          ?.copyWith(fontSize: 11, color: RvmColors.ink)),
                  if (days.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(days,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                              fontSize: 11, color: RvmColors.muted)),
                    ),
                  ] else
                    const Spacer(),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(Icons.calendar_month_outlined,
                      size: 13, color: RvmColors.muted),
                  const SizedBox(width: 4),
                  Text(dates.isEmpty ? 'Dates not set' : dates,
                      style: text.bodySmall
                          ?.copyWith(fontSize: 11, color: RvmColors.ink)),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: RvmColors.line),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Faculty: ${batch.facultyName ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                          fontSize: 11, color: RvmColors.muted),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => context.push('/work/batch/${batch.id}/mark',
                        extra: batch.name),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('View logs',
                              style: text.labelSmall?.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: RvmColors.clay)),
                          const Icon(Icons.chevron_right_rounded,
                              size: 15, color: RvmColors.clay),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      'completed' => ('COMPLETED', RvmColors.clay, RvmColors.claySoft),
      'upcoming' => ('UPCOMING', RvmColors.info, RvmColors.infoSoft),
      _ => ('ACTIVE', RvmColors.success, RvmColors.successSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 8.5,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w800,
              color: fg)),
    );
  }
}

class _RollChip extends StatelessWidget {
  const _RollChip({required this.number});
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(right: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: RvmColors.ivory,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: RvmColors.line),
      ),
      child: Text('$number',
          style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: RvmColors.ink)),
    );
  }
}

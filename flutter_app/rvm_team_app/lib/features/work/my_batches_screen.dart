import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';

/// The batches the signed-in faculty/HOD teaches (`GET /api/batches` — already
/// filtered to the caller's own batches by the server). Timings come from the
/// same rows (`start_time`, `end_time`, `days_of_week`); the status and search
/// filters run client-side over the loaded list.
class MyBatchesScreen extends StatelessWidget {
  const MyBatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My batches')),
      body: BlocProvider(
        create: (_) => getIt<MyBatchesBloc>()..add(const LoadRequested()),
        child: const _BatchesView(),
      ),
    );
  }
}

class _BatchesView extends StatefulWidget {
  const _BatchesView();

  @override
  State<_BatchesView> createState() => _BatchesViewState();
}

class _BatchesViewState extends State<_BatchesView> {
  static const _statuses = ['all', 'active', 'upcoming', 'completed'];
  String _status = 'all';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<TeamBatch> _filtered(List<TeamBatch> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((b) {
      if (_status != 'all' &&
          (b.status ?? 'active').toLowerCase() != _status) {
        return false;
      }
      if (q.isEmpty) return true;
      return b.name.toLowerCase().contains(q) ||
          (b.skillName?.toLowerCase().contains(q) ?? false) ||
          (b.facultyName?.toLowerCase().contains(q) ?? false);
    }).toList(growable: false);
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
              message:
                  state.failure?.message ?? 'Could not load your batches.',
              onRetry: () =>
                  context.read<MyBatchesBloc>().add(const LoadRefreshed()));
        }
        if (data == null || data.isEmpty) {
          return const AppEmpty(
              message: 'No batches are assigned to you.',
              icon: Icons.menu_book_outlined);
        }
        final shown = _filtered(data);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  hintText: 'Search batch, skill or faculty',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  for (final s in _statuses)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s == 'all'
                            ? 'All'
                            : s[0].toUpperCase() + s.substring(1)),
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                    ),
                ],
              ),
            ),
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
                              icon: Icons.filter_list_off_outlined),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: RvmSpacing.sm),
                        itemBuilder: (context, i) =>
                            _BatchTile(batch: shown[i]),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile({required this.batch});
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final time = [
      _hhmm(batch.startTime),
      _hhmm(batch.endTime)
    ].where((t) => t.isNotEmpty).join(' – ');
    final days = _shortDays(batch.daysOfWeek);
    final dates = [
      if (batch.startDate != null && batch.startDate!.isNotEmpty)
        batch.startDate!,
      if (batch.endDate != null && batch.endDate!.isNotEmpty)
        batch.endDate!,
    ].join(' → ');
    return Card(
      child: ListTile(
        onTap: () =>
            context.push('/work/batch/${batch.id}/mark', extra: batch.name),
        title: Text(batch.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (batch.skillName != null) Text(batch.skillName!),
            Text([
              '${batch.joinedCount}/${batch.students} students',
              if (batch.schedule != null) batch.schedule!,
              if (batch.substituted) 'substituted',
            ].join(' · ')),
            if (time.isNotEmpty || days.isNotEmpty || dates.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule_outlined,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [
                        if (time.isNotEmpty) time,
                        if (days.isNotEmpty) days,
                        if (dates.isNotEmpty) dates,
                      ].join(' · '),
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        isThreeLine: true,
        trailing: Chip(
          visualDensity: VisualDensity.compact,
          label: Text((batch.status ?? 'active').toUpperCase(),
              style: const TextStyle(fontSize: 10)),
          backgroundColor: scheme.surfaceContainerHighest,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}

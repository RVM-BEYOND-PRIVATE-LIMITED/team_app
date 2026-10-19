import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import 'bloc/interview_action_bloc.dart';

/// The interviewer's calendar (`GET /api/interviews`): the rounds they sit on,
/// with the two things they can do from the phone — record the outcome, or say
/// they cannot make the time (`POST /:roundId/outcome`, `/:roundId/postpone`).
class InterviewsScreen extends StatelessWidget {
  const InterviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interviews'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => context.read<InterviewsListBloc>().add(const LoadRefreshed()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocProvider(
        create: (_) => getIt<InterviewsListBloc>()..add(const LoadRequested()),
        child: BlocBuilder<InterviewsListBloc, LoadState<List<InterviewRound>>>(
          builder: (context, state) {
            return switch (state.status) {
              LoadStatus.loading || LoadStatus.initial => const AppLoading(),
              LoadStatus.failure => AppError(
                  message: state.failure?.message ?? 'Could not load your interviews.',
                  onRetry: () => context.read<InterviewsListBloc>().add(const LoadRefreshed()),
                ),
              LoadStatus.empty => const AppEmpty(message: 'No interviews on your calendar.', icon: Icons.event_note_outlined),
              LoadStatus.success => RefreshIndicator(
                  onRefresh: () async => context.read<InterviewsListBloc>().add(const LoadRefreshed()),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.data!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
                    itemBuilder: (context, i) => _RoundTile(round: state.data![i]),
                  ),
                ),
            };
          },
        ),
      ),
    );
  }
}

class _RoundTile extends StatelessWidget {
  const _RoundTile({required this.round});
  final InterviewRound round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final held = round.scheduledAt != null && round.scheduledAt!.isBefore(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(round.candidateName ?? 'Candidate', style: Theme.of(context).textTheme.titleMedium),
            if (round.position != null)
              Text(round.position!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: RvmSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (round.roundName != null) Chip(visualDensity: VisualDensity.compact, label: Text(round.roundName!)),
                if (round.mode != null) Chip(visualDensity: VisualDensity.compact, label: Text(round.mode!)),
                if (round.scheduledAt != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.schedule, size: 16),
                    label: Text(round.scheduledAt!.toLocal().toString().substring(0, 16)),
                  ),
                if (round.status != null) Chip(visualDensity: VisualDensity.compact, label: Text(round.status!)),
              ],
            ),
            const SizedBox(height: RvmSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openOutcome(context, round),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(held ? 'Record outcome' : 'Record outcome'),
                  ),
                ),
                const SizedBox(width: RvmSpacing.sm),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _openPostpone(context, round),
                    icon: const Icon(Icons.schedule_send_outlined, size: 18),
                    label: const Text("Can't make it"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openOutcome(BuildContext context, InterviewRound round) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BlocProvider(create: (_) => getIt<InterviewActionBloc>(), child: _OutcomeSheet(round: round)),
    );
  }

  void _openPostpone(BuildContext context, InterviewRound round) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BlocProvider(create: (_) => getIt<InterviewActionBloc>(), child: _PostponeSheet(round: round)),
    );
  }
}

class _OutcomeSheet extends StatefulWidget {
  const _OutcomeSheet({required this.round});
  final InterviewRound round;
  @override
  State<_OutcomeSheet> createState() => _OutcomeSheetState();
}

class _OutcomeSheetState extends State<_OutcomeSheet> {
  String _outcome = 'select';
  final _remarks = TextEditingController();

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InterviewActionBloc, InterviewActionState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == WriteStatus.success) {
          context.read<InterviewsListBloc>().add(const LoadRefreshed());
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.message ?? 'Saved.')));
        } else if (s.status == WriteStatus.failure && s.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.error!)));
        }
      },
      builder: (context, s) {
        final busy = s.status == WriteStatus.submitting;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Record outcome', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(widget.round.candidateName ?? 'Candidate', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: RvmSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _outcome,
                decoration: const InputDecoration(labelText: 'Outcome'),
                items: const [
                  DropdownMenuItem(value: 'select', child: Text('Select')),
                  DropdownMenuItem(value: 'reject', child: Text('Reject')),
                  DropdownMenuItem(value: 'hold', child: Text('Hold')),
                  DropdownMenuItem(value: 'keep_in_pipeline', child: Text('Keep in pipeline')),
                  DropdownMenuItem(value: 'no_show', child: Text('No show')),
                ],
                onChanged: (v) => setState(() => _outcome = v ?? 'select'),
              ),
              const SizedBox(height: RvmSpacing.sm),
              TextField(
                controller: _remarks,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'One line of feedback'),
              ),
              const SizedBox(height: RvmSpacing.md),
              FilledButton(
                onPressed: busy || _remarks.text.trim().isEmpty
                    ? null
                    : () => context.read<InterviewActionBloc>().add(InterviewOutcomeSubmitted(
                          roundId: widget.round.id,
                          outcome: _outcome,
                          remarks: _remarks.text.trim(),
                        )),
                child: const Text('Save outcome'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PostponeSheet extends StatefulWidget {
  const _PostponeSheet({required this.round});
  final InterviewRound round;
  @override
  State<_PostponeSheet> createState() => _PostponeSheetState();
}

class _PostponeSheetState extends State<_PostponeSheet> {
  DateTime? _when;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      initialDate: now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() => _when = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InterviewActionBloc, InterviewActionState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == WriteStatus.success) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.message ?? 'Requested.')));
        } else if (s.status == WriteStatus.failure && s.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.error!)));
        }
      },
      builder: (context, s) {
        final busy = s.status == WriteStatus.submitting;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("I can't make this time", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(widget.round.candidateName ?? 'Candidate', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: RvmSpacing.md),
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(_when == null ? 'Propose a new date & time' : _when!.toLocal().toString().substring(0, 16)),
              ),
              const SizedBox(height: RvmSpacing.sm),
              TextField(
                controller: _reason,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Why (HR needs the reason)'),
              ),
              const SizedBox(height: RvmSpacing.md),
              FilledButton(
                onPressed: busy || _when == null || _reason.text.trim().isEmpty
                    ? null
                    : () => context.read<InterviewActionBloc>().add(InterviewPostponeSubmitted(
                          roundId: widget.round.id,
                          proposedAt: _when!,
                          reason: _reason.text.trim(),
                        )),
                child: const Text('Send request'),
              ),
            ],
          ),
        );
      },
    );
  }
}

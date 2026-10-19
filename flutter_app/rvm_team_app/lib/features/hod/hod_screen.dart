import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/team_permissions.dart';
import '../../bloc/team_auth_bloc.dart';
import '../../domain/models.dart';
import '../../injection.dart';
import 'bloc/hod_write_bloc.dart';

/// The HOD / Faculty Development work area: the to-do list, pending interview
/// verdicts, and the quick 1-on-1 / risk log and day comment. Everything here
/// runs on endpoints that exist in the Scheduler today.
class HodScreen extends StatelessWidget {
  const HodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.read<TeamAuthBloc>().state.identity?.role ?? AppRole.unknown;
    final canWrite = TeamPermissions.forRole(role).canWriteHod;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Development'),
        actions: [
          if (canWrite) ...[
            IconButton(
              tooltip: 'New risk log / 1-on-1',
              onPressed: () => _openRiskLog(context),
              icon: const Icon(Icons.health_and_safety_outlined),
            ),
            IconButton(
              tooltip: 'Comment on a team member',
              onPressed: () => _openComment(context),
              icon: const Icon(Icons.rate_review_outlined),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<HodOverviewBloc>().add(const LoadRefreshed());
          context.read<HodInterviewsBloc>().add(const LoadRefreshed());
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            BlocProvider(
              create: (_) => getIt<HodOverviewBloc>()..add(const LoadRequested()),
              child: const _OverviewSection(),
            ),
            const SizedBox(height: RvmSpacing.md),
            BlocProvider(
              create: (_) => getIt<HodInterviewsBloc>()..add(const LoadRequested()),
              child: _InterviewsSection(canWrite: canWrite, onVerdict: (i) => _openVerdict(context, i)),
            ),
          ],
        ),
      ),
    );
  }

  void _openRiskLog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BlocProvider(create: (_) => getIt<HodWriteBloc>(), child: const _RiskLogSheet()),
    );
  }

  void _openComment(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BlocProvider(create: (_) => getIt<HodWriteBloc>(), child: const _CommentSheet()),
    );
  }

  void _openVerdict(BuildContext context, HodInterview interview) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BlocProvider(
        create: (_) => getIt<HodWriteBloc>(),
        child: _VerdictSheet(interview: interview, onDone: () => context.read<HodInterviewsBloc>().add(const LoadRefreshed())),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
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

class _OverviewSection extends StatelessWidget {
  const _OverviewSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HodOverviewBloc, LoadState<HodOverview>>(
      builder: (context, state) {
        return _SectionCard(
          title: 'To-do this month',
          child: switch (state.status) {
            LoadStatus.loading || LoadStatus.initial =>
              const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            LoadStatus.failure => Text(state.failure?.message ?? 'Could not load the overview.'),
            LoadStatus.empty => const Text('Nothing outstanding.'),
            LoadStatus.success => state.data!.actions.isEmpty
                ? const Text('Nothing outstanding.')
                : Column(
                    children: [
                      for (final a in state.data!.actions)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: switch (a.severity) {
                              'high' => Theme.of(context).colorScheme.errorContainer,
                              _ => Theme.of(context).colorScheme.surfaceContainerHighest,
                            },
                            child: Text('${a.count}', style: const TextStyle(fontSize: 13)),
                          ),
                          title: Text(a.label),
                          subtitle: a.detail == null ? null : Text(a.detail!, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
          },
        );
      },
    );
  }
}

class _InterviewsSection extends StatelessWidget {
  const _InterviewsSection({required this.onVerdict, required this.canWrite});
  final void Function(HodInterview) onVerdict;
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HodInterviewsBloc, LoadState<List<HodInterview>>>(
      builder: (context, state) {
        return _SectionCard(
          title: 'Interview verdicts',
          child: switch (state.status) {
            LoadStatus.loading || LoadStatus.initial =>
              const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            LoadStatus.failure => Text(state.failure?.message ?? 'Could not load interviews.'),
            LoadStatus.empty => const Text('No interviews routed to you.'),
            LoadStatus.success => Column(
                children: [
                  for (final i in state.data!)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(i.candidateName ?? 'Candidate'),
                      subtitle: Text([
                        if (i.position != null) i.position!,
                        if (i.interviewDate != null) i.interviewDate!,
                        if (i.slaBreached) 'SLA breached',
                      ].join(' · ')),
                      trailing: i.pending
                          ? (canWrite
                              ? FilledButton.tonal(onPressed: () => onVerdict(i), child: const Text('Verdict'))
                              : const Chip(visualDensity: VisualDensity.compact, label: Text('PENDING', style: TextStyle(fontSize: 10))))
                          : Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text((i.verdict ?? '').toUpperCase(), style: const TextStyle(fontSize: 10)),
                            ),
                    ),
                ],
              ),
          },
        );
      },
    );
  }
}

class _FacultyDropdown extends StatelessWidget {
  const _FacultyDropdown({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<HodFacultyOptionsBloc>()..add(const LoadRequested()),
      child: BlocBuilder<HodFacultyOptionsBloc, LoadState<List<FacultyOption>>>(
        builder: (context, state) {
          final options = state.data ?? const <FacultyOption>[];
          return DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Faculty'),
            items: [for (final f in options) DropdownMenuItem(value: f.id, child: Text(f.name, overflow: TextOverflow.ellipsis))],
            onChanged: onChanged,
          );
        },
      ),
    );
  }
}

class _RiskLogSheet extends StatefulWidget {
  const _RiskLogSheet();
  @override
  State<_RiskLogSheet> createState() => _RiskLogSheetState();
}

class _RiskLogSheetState extends State<_RiskLogSheet> {
  String? _facultyId;
  String _entryType = 'one_on_one';
  String _riskLevel = 'none';
  final _signal = TextEditingController();
  final _action = TextEditingController();
  bool _escalated = false;

  @override
  void dispose() {
    _signal.dispose();
    _action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HodWriteBloc, HodWriteState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == WriteStatus.success) {
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Risk log / 1-on-1', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: RvmSpacing.md),
                _FacultyDropdown(value: _facultyId, onChanged: (v) => setState(() => _facultyId = v)),
                const SizedBox(height: RvmSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _entryType,
                  decoration: const InputDecoration(labelText: 'Entry type'),
                  items: const [
                    DropdownMenuItem(value: 'one_on_one', child: Text('1-on-1')),
                    DropdownMenuItem(value: 'observation', child: Text('Observation')),
                    DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
                  ],
                  onChanged: (v) => setState(() => _entryType = v ?? 'one_on_one'),
                ),
                const SizedBox(height: RvmSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _riskLevel,
                  decoration: const InputDecoration(labelText: 'Risk level'),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('None')),
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (v) => setState(() => _riskLevel = v ?? 'none'),
                ),
                const SizedBox(height: RvmSpacing.sm),
                TextField(controller: _signal, maxLines: 2, decoration: const InputDecoration(labelText: 'Signal observed')),
                const SizedBox(height: RvmSpacing.sm),
                TextField(controller: _action, maxLines: 2, decoration: const InputDecoration(labelText: 'Action taken')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Escalated'),
                  value: _escalated,
                  onChanged: (v) => setState(() => _escalated = v),
                ),
                const SizedBox(height: RvmSpacing.sm),
                FilledButton(
                  onPressed: busy || _facultyId == null
                      ? null
                      : () => context.read<HodWriteBloc>().add(RiskLogSubmitted(
                            facultyId: _facultyId!,
                            entryType: _entryType,
                            riskLevel: _riskLevel,
                            signal: _signal.text.trim().isEmpty ? null : _signal.text.trim(),
                            actionTaken: _action.text.trim().isEmpty ? null : _action.text.trim(),
                            escalated: _escalated,
                          )),
                  child: const Text('Save log'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CommentSheet extends StatefulWidget {
  const _CommentSheet();
  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  String? _facultyId;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HodWriteBloc, HodWriteState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == WriteStatus.success) {
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
              Text('Comment on a team member', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: RvmSpacing.md),
              _FacultyDropdown(value: _facultyId, onChanged: (v) => setState(() => _facultyId = v)),
              const SizedBox(height: RvmSpacing.sm),
              TextField(controller: _comment, maxLines: 3, decoration: const InputDecoration(labelText: 'What happened today')),
              const SizedBox(height: RvmSpacing.md),
              FilledButton(
                onPressed: busy || _facultyId == null || _comment.text.trim().isEmpty
                    ? null
                    : () => context.read<HodWriteBloc>().add(
                          FacultyCommentSubmitted(facultyId: _facultyId!, comment: _comment.text.trim()),
                        ),
                child: const Text('Save comment'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VerdictSheet extends StatefulWidget {
  const _VerdictSheet({required this.interview, required this.onDone});
  final HodInterview interview;
  final VoidCallback onDone;

  @override
  State<_VerdictSheet> createState() => _VerdictSheetState();
}

class _VerdictSheetState extends State<_VerdictSheet> {
  String _verdict = 'select';
  final _feedback = TextEditingController();

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HodWriteBloc, HodWriteState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == WriteStatus.success) {
          widget.onDone();
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
              Text('Interview verdict', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(widget.interview.candidateName ?? 'Candidate', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: RvmSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _verdict,
                decoration: const InputDecoration(labelText: 'Verdict'),
                items: const [
                  DropdownMenuItem(value: 'select', child: Text('Select')),
                  DropdownMenuItem(value: 'reject', child: Text('Reject')),
                  DropdownMenuItem(value: 'hold', child: Text('Hold')),
                  DropdownMenuItem(value: 'no_show', child: Text('No show')),
                ],
                onChanged: (v) => setState(() => _verdict = v ?? 'select'),
              ),
              const SizedBox(height: RvmSpacing.sm),
              TextField(
                controller: _feedback,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'One line of technical justification'),
              ),
              const SizedBox(height: RvmSpacing.md),
              FilledButton(
                onPressed: busy || _feedback.text.trim().isEmpty
                    ? null
                    : () => context.read<HodWriteBloc>().add(VerdictSubmitted(
                          id: widget.interview.id,
                          verdict: _verdict,
                          feedback: _feedback.text.trim(),
                        )),
                child: const Text('Record verdict'),
              ),
            ],
          ),
        );
      },
    );
  }
}

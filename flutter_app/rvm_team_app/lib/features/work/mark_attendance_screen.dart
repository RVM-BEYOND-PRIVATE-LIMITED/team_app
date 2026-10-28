import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app_feedback.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import 'bloc/absent_remark_bloc.dart';
import 'bloc/mark_attendance_bloc.dart';

String _batchTitle(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return 'Mark attendance';
  return trimmed.replaceAll('_', ' ');
}

/// Mark one batch's student attendance for today through the ESS
/// (`GET /me/batches/{id}/roster`, `POST /me/batches/{id}/attendance`, H1).
class MarkAttendanceScreen extends StatelessWidget {
  const MarkAttendanceScreen(
      {super.key, required this.batchId, this.batchName});
  final String batchId;
  final String? batchName;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return BlocProvider(
      create: (_) => getIt<MarkAttendanceBloc>(param1: batchId, param2: today)
        ..add(const MarkRosterRequested()),
      child: BlocListener<MarkAttendanceBloc, MarkAttendanceState>(
        listenWhen: (a, b) => a.writeStatus != b.writeStatus,
        listener: (context, state) {
          if (state.writeStatus == WriteStatus.success) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                  const SnackBar(content: Text('Attendance saved.')));
          } else if (state.writeStatus == WriteStatus.failure &&
              state.error != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.error!)));
          }
        },
        child: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text(_batchTitle(batchName)),
              actions: [
                BlocBuilder<MarkAttendanceBloc, MarkAttendanceState>(
                  buildWhen: (a, b) => a.canEdit != b.canEdit,
                  builder: (context, state) => IconButton(
                    tooltip: 'All present',
                    onPressed: state.canEdit
                        ? () => context
                            .read<MarkAttendanceBloc>()
                            .add(const MarkAllPresent())
                        : null,
                    icon: const Icon(Icons.done_all),
                  ),
                ),
              ],
            ),
            body: BlocBuilder<MarkAttendanceBloc, MarkAttendanceState>(
              builder: (context, state) {
                if (state.status == LoadStatus.initial ||
                    (state.status == LoadStatus.loading &&
                        state.students.isEmpty)) {
                  return const AppLoading(label: 'Loading roster');
                }
                if (state.status == LoadStatus.failure &&
                    state.students.isEmpty) {
                  return AppError(
                    message: state.error ?? 'Could not load the roster.',
                    onRetry: () => context
                        .read<MarkAttendanceBloc>()
                        .add(const MarkRosterRequested()),
                  );
                }
                if (state.students.isEmpty) {
                  return const AppEmpty(
                      message: 'No students are linked to this batch.',
                      icon: Icons.people_outline);
                }
                return _Roster(state: state);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Roster extends StatelessWidget {
  const _Roster({required this.state});
  final MarkAttendanceState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (!state.canEdit)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    'This day is already marked. The marks are locked; an absent student’s reason can still be updated.'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text('${state.presentCount} of ${state.students.length} present',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: state.students.length,
            itemBuilder: (context, i) {
              final s = state.students[i];
              final present = state.present[s.id] ?? false;
              final canRemark = s.isAbsent;
              return CheckboxListTile(
                value: present,
                onChanged: state.canEdit
                    ? (_) => context
                        .read<MarkAttendanceBloc>()
                        .add(MarkToggled(s.id))
                    : null,
                title: Text(s.fullName ?? 'Student'),
                subtitle: Text([
                  if (s.admissionNumber != null) s.admissionNumber!,
                  if (s.isAbsent && (s.absentReason?.isNotEmpty ?? false))
                    'reason: ${s.absentReason}',
                ].join(' · ')),
                controlAffinity: ListTileControlAffinity.leading,
                secondary: canRemark
                    ? IconButton(
                        tooltip: 'Absent reason',
                        icon: const Icon(Icons.edit_note_outlined),
                        onPressed: () => _openRemark(context, s),
                      )
                    : null,
              );
            },
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 16 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: FilledButton.icon(
            onPressed:
                state.canEdit && state.writeStatus != WriteStatus.submitting
                    ? () => context
                        .read<MarkAttendanceBloc>()
                        .add(const MarkSubmitted())
                    : null,
            icon: state.writeStatus == WriteStatus.submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Save attendance'),
          ),
        ),
      ],
    );
  }

  Future<void> _openRemark(BuildContext context, ClassRosterStudent s) async {
    final bloc = context.read<MarkAttendanceBloc>();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BlocProvider(
        create: (_) => getIt<AbsentRemarkBloc>(),
        child: _RemarkSheet(
          batchId: bloc.batchId,
          date: bloc.dateIso,
          student: s,
        ),
      ),
    );
    if (saved == true && context.mounted) {
      bloc.add(const MarkRosterRequested());
    }
  }
}

/// The mandatory absent reason for one student
/// (`PATCH /api/ess/me/batches/{id}/attendance/{date}/remarks`).
class _RemarkSheet extends StatefulWidget {
  const _RemarkSheet({
    required this.batchId,
    required this.date,
    required this.student,
  });

  final String batchId;
  final String date;
  final ClassRosterStudent student;

  @override
  State<_RemarkSheet> createState() => _RemarkSheetState();
}

class _RemarkSheetState extends State<_RemarkSheet> {
  final _reason = TextEditingController();
  final _followUp = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    _followUp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AbsentRemarkBloc, AbsentRemarkState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, state) {
        if (state.status == WriteStatus.success) {
          showAppMessage('Absent reason saved.');
          Navigator.of(context).pop(true);
        } else if (state.status == WriteStatus.failure && state.error != null) {
          showAppMessage(state.error!);
        }
      },
      builder: (context, state) {
        final busy = state.status == WriteStatus.submitting;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Absent reason',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(widget.student.fullName ?? 'Student',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: RvmSpacing.md),
              TextField(
                controller: _reason,
                maxLength: 500,
                decoration:
                    const InputDecoration(labelText: 'Reason for absence'),
              ),
              const SizedBox(height: RvmSpacing.sm),
              TextField(
                controller: _followUp,
                maxLength: 1000,
                decoration: const InputDecoration(
                    labelText: 'Follow-up comment (optional)'),
              ),
              const SizedBox(height: RvmSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          final reason = _reason.text.trim();
                          if (reason.length < 3) {
                            showAppMessage(
                                'Enter a reason of at least 3 characters.');
                            return;
                          }
                          context.read<AbsentRemarkBloc>().add(
                                AbsentRemarkSubmitted(
                                  batchId: widget.batchId,
                                  date: widget.date,
                                  studentId: widget.student.id,
                                  reason: reason,
                                  followUp: _followUp.text.trim().isEmpty
                                      ? null
                                      : _followUp.text.trim(),
                                ),
                              );
                        },
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save reason'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

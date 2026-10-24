import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app_feedback.dart';
import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import 'bloc/absent_remark_bloc.dart';
import 'bloc/mark_attendance_bloc.dart';

/// Mark one batch's student attendance for today
/// (`GET /api/attendance/batch/:id/daily`, `POST /api/attendance`).
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
              title: Text(batchName ?? 'Mark attendance'),
              actions: [
                IconButton(
                  tooltip: 'All present',
                  onPressed: () => context
                      .read<MarkAttendanceBloc>()
                      .add(const MarkAllPresent()),
                  icon: const Icon(Icons.done_all),
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
              final present = state.present[s.studentId] ?? false;
              final disabled = !s.isEligible || s.isOnHold;
              final canRemark = !present && s.attendanceId != null && !disabled;
              return CheckboxListTile(
                value: present,
                onChanged: disabled
                    ? null
                    : (_) => context
                        .read<MarkAttendanceBloc>()
                        .add(MarkToggled(s.studentId)),
                title: Text(s.name),
                subtitle: Text([
                  if (s.rollCode != null) s.rollCode!,
                  if (s.isOnHold) 'on hold',
                  if (s.notYetJoined) 'not yet joined',
                  if (!present && (s.absentReason?.isNotEmpty ?? false))
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
            onPressed: state.writeStatus == WriteStatus.submitting
                ? null
                : () => context
                    .read<MarkAttendanceBloc>()
                    .add(const MarkSubmitted()),
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

  void _openRemark(BuildContext context, AttendanceStudent s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BlocProvider(
        create: (_) => getIt<AbsentRemarkBloc>(),
        child: _RemarkSheet(student: s),
      ),
    );
  }
}

/// The mandatory absent reason for one student (`PATCH /api/attendance/remarks`).
class _RemarkSheet extends StatefulWidget {
  const _RemarkSheet({required this.student});
  final AttendanceStudent student;

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
          Navigator.of(context).pop();
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
              Text(widget.student.name,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: RvmSpacing.md),
              TextField(
                controller: _reason,
                maxLength: 200,
                decoration:
                    const InputDecoration(labelText: 'Reason for absence'),
              ),
              const SizedBox(height: RvmSpacing.sm),
              TextField(
                controller: _followUp,
                maxLength: 200,
                decoration: const InputDecoration(
                    labelText: 'Follow-up comment (optional)'),
              ),
              const SizedBox(height: RvmSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => context
                          .read<AbsentRemarkBloc>()
                          .add(AbsentRemarkSubmitted(
                            attendanceId: widget.student.attendanceId!,
                            reason: _reason.text.trim().isEmpty
                                ? null
                                : _reason.text.trim(),
                            followUp: _followUp.text.trim().isEmpty
                                ? null
                                : _followUp.text.trim(),
                          )),
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

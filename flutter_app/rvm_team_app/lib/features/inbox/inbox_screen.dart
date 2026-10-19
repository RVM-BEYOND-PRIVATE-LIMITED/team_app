import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import 'bloc/task_action_bloc.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<InboxBloc>()..add(const LoadRequested()),
      child: Scaffold(
        body: Column(
          children: [
            TeamPageHeader(
              title: 'Inbox',
              subtitle: const Text('Priority tasks assigned to you'),
              actions: [
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => context.read<InboxBloc>().add(const LoadRefreshed()),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ],
            ),
            Expanded(
              child: BlocBuilder<InboxBloc, LoadState<PriorityInbox>>(
                builder: (context, state) {
                  return switch (state.status) {
                    LoadStatus.loading || LoadStatus.initial =>
                      const AppLoading(label: 'Loading your tasks'),
                    LoadStatus.failure => AppError(
                        message: state.failure?.message ?? 'Could not load your inbox.',
                        onRetry: () => context.read<InboxBloc>().add(const LoadRefreshed()),
                      ),
                    LoadStatus.empty => const AppEmpty(
                        message:
                            'Nothing has landed on you yet. Priority tasks set by the CEO, HoO or super admin appear here.',
                        icon: Icons.inbox_outlined,
                      ),
                    LoadStatus.success => _Inbox(inbox: state.data!),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Inbox extends StatelessWidget {
  const _Inbox({required this.inbox});
  final PriorityInbox inbox;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => context.read<InboxBloc>().add(const LoadRefreshed()),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${inbox.outstanding} outstanding · ${inbox.unread} unread',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: RvmSpacing.sm),
          if (inbox.tasks.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 40), child: AppEmpty(message: 'No tasks right now.'))
          else
            for (final t in inbox.tasks) _TaskTile(task: t),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final PriorityTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = task.isDone;
    return Card(
      child: ListTile(
        onTap: () => _open(context),
        leading: CircleAvatar(
          backgroundColor: switch (task.priority) {
            'urgent' => scheme.errorContainer,
            'high' => RvmColors.teamSeed.withValues(alpha: 0.16),
            _ => scheme.surfaceContainerHighest,
          },
          child: Icon(done ? Icons.check : Icons.flag_outlined,
              color: done ? RvmColors.success : scheme.onSurface),
        ),
        title: Text(task.title,
            style: TextStyle(decoration: done ? TextDecoration.lineThrough : null, fontWeight: FontWeight.w600)),
        subtitle: Text([
          if (task.locationName != null) task.locationName!,
          if (task.assignedByName != null) 'by ${task.assignedByName}',
          task.priority.toUpperCase(),
          if (task.overdue) 'OVERDUE',
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BlocProvider(
        create: (_) => getIt<TaskActionBloc>(),
        child: _TaskSheet(task: task),
      ),
    );
  }
}

class _TaskSheet extends StatelessWidget {
  const _TaskSheet({required this.task});
  final PriorityTask task;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TaskActionBloc, TaskActionState>(
      listener: (context, state) {
        if (state.status == WriteStatus.success) {
          context.read<InboxBloc>().add(const LoadRefreshed());
          Navigator.of(context).pop();
        } else if (state.status == WriteStatus.failure && state.error != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.error!)));
        }
      },
      builder: (context, state) {
        final busy = state.status == WriteStatus.submitting;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: RvmSpacing.xs),
              Text([
                if (task.locationName != null) task.locationName!,
                if (task.assignedByName != null) 'Set by ${task.assignedByName}',
                if (task.taskDate != null) task.taskDate!,
              ].join(' · '), style: Theme.of(context).textTheme.bodySmall),
              if (task.notes != null && task.notes!.isNotEmpty) ...[
                const SizedBox(height: RvmSpacing.md),
                Text(task.notes!),
              ],
              if (task.progressNote != null && task.progressNote!.isNotEmpty) ...[
                const SizedBox(height: RvmSpacing.sm),
                Text('Progress: ${task.progressNote}', style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: RvmSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => _ack(context),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: Text(task.read ? 'Seen' : 'Mark seen'),
                    ),
                  ),
                  const SizedBox(width: RvmSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => _setStatus(context, task.isDone ? 'open' : 'done'),
                      icon: Icon(task.isDone ? Icons.replay : Icons.check),
                      label: Text(task.isDone ? 'Reopen' : 'Mark done'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RvmSpacing.sm),
              if (!task.isDone)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: busy ? null : () => _setStatus(context, 'in_progress'),
                    child: const Text('Mark in progress'),
                  ),
                ),
              if (busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            ],
          ),
        );
      },
    );
  }

  void _ack(BuildContext context) => context.read<TaskActionBloc>().add(TaskAcknowledged(task.id));
  void _setStatus(BuildContext context, String status) =>
      context.read<TaskActionBloc>().add(TaskStatusChanged(id: task.id, status: status));
}

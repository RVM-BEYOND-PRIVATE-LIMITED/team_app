import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import 'bloc/approvals_bloc.dart';

/// D1/H6: the approvals Inbox — a manager's own reports, or HR-wide. Backend: `/api/ess/approvals`.
class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ApprovalsBloc>()..add(const ApprovalsLoadRequested()),
      child: const _ApprovalsView(),
    );
  }
}

class _ApprovalsView extends StatelessWidget {
  const _ApprovalsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Approvals',
            subtitle: const Text('Decide your team\'s requests'),
            actions: [
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => context.read<ApprovalsBloc>().add(const ApprovalsRefreshed()),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ],
          ),
          Expanded(
            child: BlocConsumer<ApprovalsBloc, ApprovalsState>(
              listenWhen: (a, b) => a.decidedNonce != b.decidedNonce || a.actionFailure != b.actionFailure,
              listener: (context, state) {
                final msg = state.actionFailure?.message;
                if (msg != null) {
                  ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(msg)));
                } else if (state.decidedNonce > 0) {
                  ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(const SnackBar(content: Text('Decision saved.')));
                }
              },
              builder: (context, state) => _body(context, state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ApprovalsState state) {
    if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) return const AppLoading();
    if (state.status == LoadStatus.failure) {
      return AppError(
        message: state.failure?.message ?? 'Could not load approvals.',
        onRetry: () => context.read<ApprovalsBloc>().add(const ApprovalsRefreshed()),
      );
    }
    final inbox = state.inbox;
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(RvmSpacing.md, RvmSpacing.sm, RvmSpacing.md, 0),
          child: Row(
            children: [
              for (final f in const ['pending', 'approved', 'rejected', 'all'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f[0].toUpperCase() + f.substring(1)),
                    selected: state.filter == f,
                    onSelected: (_) => context.read<ApprovalsBloc>().add(ApprovalsFiltered(f)),
                  ),
                ),
            ],
          ),
        ),
        if (inbox != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(RvmSpacing.md, RvmSpacing.sm, RvmSpacing.md, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${inbox.attendance} attendance · ${inbox.leave} leave pending',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        Expanded(
          child: inbox == null || inbox.requests.isEmpty
              ? const AppEmpty(icon: Icons.task_alt, message: 'Nothing to decide here.')
              : RefreshIndicator(
                  onRefresh: () async => context.read<ApprovalsBloc>().add(const ApprovalsRefreshed()),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(RvmSpacing.md),
                    itemCount: inbox.requests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
                    itemBuilder: (context, i) => _ApprovalCard(request: inbox.requests[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.request});
  final EssRequest request;

  @override
  Widget build(BuildContext context) {
    final ctx = request.context;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(request.employee?.fullName ?? 'Employee', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text('${request.typeLabel} · ${request.day}', style: Theme.of(context).textTheme.bodyMedium),
            Text(request.reason, style: Theme.of(context).textTheme.bodySmall),
            if (ctx != null) ...[
              const SizedBox(height: 4),
              Text([
                if (ctx.monthLimit != null) '${ctx.typeThisMonth} of ${ctx.monthLimit} this month',
                if (ctx.late != null) 'Late ${ctx.late!.lateMinutes ?? ''} min',
                if (ctx.othersOffCount > 0) '${ctx.othersOffCount} others off${ctx.othersOffNames.isEmpty ? '' : ' (${ctx.othersOffNames.join(', ')})'}',
              ].where((s) => s.isNotEmpty).join(' · '), style: Theme.of(context).textTheme.labelSmall),
            ],
            if (request.status == 'pending') ...[
              const SizedBox(height: RvmSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => context.read<ApprovalsBloc>().add(
                            ApprovalDecided(family: request.family, id: request.id, decision: 'approve'),
                          ),
                      child: const Text('Approve'),
                    ),
                  ),
                  const SizedBox(width: RvmSpacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reject(context),
                      child: const Text('Reject'),
                    ),
                  ),
                ],
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.read<ApprovalsBloc>().add(ApprovalArchived(family: request.family, id: request.id)),
                  child: const Text('Archive'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _reject(BuildContext context) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reason to reject'),
        content: TextField(controller: controller, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: 'At least 3 characters')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Reject')),
        ],
      ),
    );
    if (note == null || !context.mounted) return;
    if (note.length < 3) {
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(const SnackBar(content: Text('Please give a reason.')));
      return;
    }
    context.read<ApprovalsBloc>().add(ApprovalDecided(family: request.family, id: request.id, decision: 'reject', note: note));
  }
}

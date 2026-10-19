import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import 'bloc/requests_bloc.dart';
import 'raise_request_sheet.dart';

/// C1–C5: my requests (on duty, fix a day, excuse a late, CL, leave without pay), the month's
/// balances, raise and withdraw. Backend: `/attendance-requests`, `/leave-requests`,
/// `/leave/balances` (Phase 1C).
class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<RequestsBloc>()..add(const RequestsLoadRequested()),
      child: const _RequestsView(),
    );
  }
}

class _RequestsView extends StatelessWidget {
  const _RequestsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Requests',
            subtitle: const Text('Attendance fixes and leave'),
            actions: [
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => context.read<RequestsBloc>().add(const RequestsRefreshed()),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ],
          ),
          Expanded(
            child: BlocConsumer<RequestsBloc, RequestsState>(
              listenWhen: (a, b) => a.createdNonce != b.createdNonce || a.submitFailure != b.submitFailure,
              listener: (context, state) {
                final msg = state.submitFailure?.message;
                if (msg != null) {
                  ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(msg)));
                } else if (state.createdNonce > 0) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(content: Text('Request sent to your approver.')));
                }
              },
              builder: (context, state) => _body(context, state),
            ),
          ),
        ],
      ),
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton.extended(
          onPressed: () => showRaiseRequestSheet(context),
          icon: const Icon(Icons.add),
          label: const Text('New request'),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, RequestsState state) {
    if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) return const AppLoading();
    if (state.status == LoadStatus.failure) {
      return AppError(
        message: state.failure?.message ?? 'Could not load your requests.',
        onRetry: () => context.read<RequestsBloc>().add(const RequestsRefreshed()),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => context.read<RequestsBloc>().add(const RequestsRefreshed()),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, 96),
        children: [
          if (state.balances != null) _BalancesCard(balances: state.balances!),
          const SizedBox(height: RvmSpacing.md),
          Text('My requests', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: RvmSpacing.sm),
          if (state.requests.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: AppEmpty(icon: Icons.event_note_outlined, message: 'No requests yet.'),
            )
          else
            for (final r in state.requests) ...[
              _RequestCard(request: r),
              const SizedBox(height: RvmSpacing.sm),
            ],
        ],
      ),
    );
  }
}

class _BalancesCard extends StatelessWidget {
  const _BalancesCard({required this.balances});
  final LeaveBalances balances;

  @override
  Widget build(BuildContext context) {
    final offered = balances.types.where((t) => t.offered).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This month · ${balances.month}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: RvmSpacing.sm),
            if (offered.isEmpty)
              const Text('No request types are available to your login.')
            else
              for (final t in offered)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(t.label)),
                      Text(t.allowed == null
                          ? 'Used ${t.used}${t.pending > 0 ? ' (+${t.pending} pending)' : ''}'
                          : '${t.remaining} of ${t.allowed} left${t.pending > 0 ? ' · ${t.pending} pending' : ''}'),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});
  final EssRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (request.status) {
      'approved' => ('Approved', RvmColors.success),
      'rejected' => ('Rejected', RvmColors.danger),
      'withdrawn' || 'cancelled' => (request.status == 'withdrawn' ? 'Withdrawn' : 'Cancelled', scheme.onSurfaceVariant),
      _ => ('Pending', scheme.primary),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(request.typeLabel, style: Theme.of(context).textTheme.titleMedium)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(RvmRadii.sm)),
                  child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${request.day} · ${request.reason}', style: Theme.of(context).textTheme.bodyMedium),
            if (request.decisionNote != null)
              Text('Decision: ${request.decisionNote}${request.decidedByName != null ? ' — ${request.decidedByName}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (request.isPending)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.read<RequestsBloc>().add(RequestWithdrawRequested(family: request.family, id: request.id)),
                  child: const Text('Withdraw'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

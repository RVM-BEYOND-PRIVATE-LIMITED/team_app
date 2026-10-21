import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import 'bloc/helpdesk_bloc.dart';
import 'raise_ticket_sheet.dart';

/// Phase 2B: raise a ticket, follow its thread, and (for agents) work the queue.
class HelpdeskScreen extends StatelessWidget {
  const HelpdeskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<HelpdeskBloc>()..add(const HelpdeskLoadRequested()),
      child: const _HelpdeskView(),
    );
  }
}

class _HelpdeskView extends StatelessWidget {
  const _HelpdeskView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HelpdeskBloc, HelpdeskState>(
      listenWhen: (a, b) =>
          a.actionFailure != b.actionFailure || a.actionNonce != b.actionNonce,
      listener: (context, state) {
        final msg = state.actionFailure?.message;
        if (msg != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(msg)));
        } else if (state.actionNonce > 0) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('Ticket sent.')));
        }
      },
      builder: (context, state) => Scaffold(
        body: Column(
          children: [
            TeamPageHeader(
              title: 'Helpdesk',
              subtitle: const Text('Raise a ticket and follow its thread'),
              actions: [
                Builder(
                  builder: (context) => TeamHeaderAction(
                    icon: Icons.support_agent_rounded,
                    tooltip: 'Team queue',
                    onPressed: () => context.push('/helpdesk/queue'),
                  ),
                ),
                Builder(
                  builder: (context) => TeamHeaderAction(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh',
                    onPressed: () => context
                        .read<HelpdeskBloc>()
                        .add(const HelpdeskRefreshed()),
                  ),
                ),
              ],
            ),
            Expanded(child: _body(context, state)),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showRaiseTicketSheet(context),
          icon: const Icon(Icons.add),
          label: const Text('Raise a ticket'),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, HelpdeskState state) {
    if (state.status == LoadStatus.initial ||
        state.status == LoadStatus.loading) {
      return const AppLoading();
    }
    if (state.status == LoadStatus.failure) {
      return AppError(
        message: state.failure?.message ?? 'Could not load your tickets.',
        onRetry: () =>
            context.read<HelpdeskBloc>().add(const HelpdeskRefreshed()),
      );
    }
    if (state.tickets.isEmpty) {
      return const AppEmpty(
          icon: Icons.support_agent,
          message: 'No tickets yet.\nRaise one and it goes to the right team.');
    }
    return RefreshIndicator(
      onRefresh: () async =>
          context.read<HelpdeskBloc>().add(const HelpdeskRefreshed()),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, 96),
        itemCount: state.tickets.length,
        separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
        itemBuilder: (context, i) => _TicketCard(ticket: state.tickets[i]),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});
  final HelpdeskTicket ticket;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => context.push('/helpdesk/ticket/${ticket.id}'),
        title: Row(
          children: [
            Expanded(
                child: Text('${ticket.ref} · ${ticket.subject}',
                    overflow: TextOverflow.ellipsis)),
            _StatusPill(status: ticket.status),
          ],
        ),
        subtitle: Text([
          ticket.category.name,
          if (ticket.assignee != null) 'with ${ticket.assignee!.fullName}',
          if (ticket.overdue) 'overdue',
        ].where((s) => s.isNotEmpty).join(' · ')),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'open' => ('Open', RvmColors.brand),
      'in_progress' => ('In progress', RvmColors.warning),
      'on_hold' => ('On hold', RvmColors.warning),
      'resolved' => ('Resolved', RvmColors.success),
      'closed' => ('Closed', RvmColors.success),
      'withdrawn' => (
          'Withdrawn',
          Theme.of(context).colorScheme.onSurfaceVariant
        ),
      _ => (status, Theme.of(context).colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

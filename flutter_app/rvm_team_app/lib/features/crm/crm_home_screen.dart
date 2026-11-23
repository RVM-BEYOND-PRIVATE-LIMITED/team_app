import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/crm_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import 'bloc/crm_blocs.dart';
import 'crm_quiz_screen.dart';
import 'crm_shared.dart';

/// `/crm` — the dialer's home (team_app #51, item 3): Start, Break, today's
/// counts, Auto-dial and Add lead. A call left open is shown first, so a form
/// lost to an app kill can be finished.
class CrmHomeScreen extends StatelessWidget {
  const CrmHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = crmRepositoryOrNull();
    if (repository == null) {
      return const Scaffold(
        body: Center(
            child: Text('The Sales CRM is not available in this build.')),
      );
    }
    return BlocProvider(
      create: (_) => CrmHomeBloc(repository)..add(const CrmHomeLoadRequested()),
      child: const _CrmHomeView(),
    );
  }
}

class _CrmHomeView extends StatefulWidget {
  const _CrmHomeView();

  @override
  State<_CrmHomeView> createState() => _CrmHomeViewState();
}

class _CrmHomeViewState extends State<_CrmHomeView> {
  bool _openedOpenCall = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BlocConsumer<CrmHomeBloc, CrmHomeState>(
      listenWhen: (a, b) => a.message != b.message,
      listener: (context, state) {
        final message = state.message;
        if (message != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
      },
      builder: (context, state) {
        final home = state.home;
        if (state.loading && home == null) {
          return const Scaffold(body: AppLoading(label: 'Loading the CRM…'));
        }
        if (state.failure != null && home == null) {
          return Scaffold(
            appBar: _bar(context, 'Sales CRM'),
            body: crmFailure(state.failure,
                onRetry: () =>
                    context.read<CrmHomeBloc>().add(const CrmHomeRefreshed())),
          );
        }
        final open = home?.openCall;
        if (open != null && !_openedOpenCall) {
          _openedOpenCall = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.push('/crm/lead/${open.leadId}/dispose'
                  '?callId=${open.callId}&origin=dialer');
            }
          });
        }
        return Scaffold(
          backgroundColor: p.canvas,
          appBar: _bar(context, 'Sales CRM'),
          body: RefreshIndicator(
            color: p.primary,
            onRefresh: () async =>
                context.read<CrmHomeBloc>().add(const CrmHomeRefreshed()),
            child: ListView(
              padding: const EdgeInsets.all(RvmSpacing.md),
              children: [
                if (open != null) ...[
                  TeamCard(
                    color: p.warningSoft,
                    borderColor: p.warning,
                    onTap: () => context.push('/crm/lead/${open.leadId}/dispose'
                        '?callId=${open.callId}&origin=dialer'),
                    child: Row(
                      children: [
                        Icon(Icons.phone_in_talk_outlined, color: p.warning),
                        const SizedBox(width: RvmSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Finish this call',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              Text(
                                open.leadName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                  const SizedBox(height: RvmSpacing.md),
                ],
                CrmQuizCard(hasOpenCall: open != null),
                Row(
                  children: [
                    Expanded(
                      child: _CountCard(
                        label: 'Due today',
                        value: home?.followupsDueToday ?? 0,
                        icon: Icons.today_outlined,
                        onTap: () =>
                            context.push('/crm/leads?bucket=follow_up'),
                      ),
                    ),
                    const SizedBox(width: RvmSpacing.sm),
                    Expanded(
                      child: _CountCard(
                        label: 'Missed',
                        value: home?.missed ?? 0,
                        icon: Icons.alarm_off_outlined,
                        danger: true,
                        onTap: () =>
                            context.push('/crm/leads?bucket=follow_up'),
                      ),
                    ),
                    const SizedBox(width: RvmSpacing.sm),
                    Expanded(
                      child: _CountCard(
                        label: 'Callbacks',
                        value: home?.callbacksWaiting ?? 0,
                        icon: Icons.phone_callback_outlined,
                        onTap: () =>
                            context.push('/crm/leads?bucket=uncontacted'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RvmSpacing.lg),
                FilledButton.icon(
                  onPressed: state.busy
                      ? null
                      : () => _startNext(context, bucket: null),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: p.primary,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start calling'),
                ),
                const SizedBox(height: RvmSpacing.sm),
                OutlinedButton.icon(
                  onPressed: state.busy
                      ? null
                      : () => context
                          .read<CrmHomeBloc>()
                          .add(CrmBreakToggled(!(home?.onBreak ?? false))),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  icon: Icon((home?.onBreak ?? false)
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline),
                  label: Text(
                      (home?.onBreak ?? false) ? 'End break' : 'Go on break'),
                ),
                const SizedBox(height: RvmSpacing.lg),
                TeamCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: state.autoDial,
                        onChanged: (on) => context
                            .read<CrmHomeBloc>()
                            .add(CrmAutoDialToggled(on)),
                        title: const Text('Auto-dial'),
                        subtitle: const Text(
                            'After saving a form, open the next lead at once.'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_add_alt_outlined),
                        title: const Text('Add a lead'),
                        subtitle: const Text('Walk-in, enquiry or a reference'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/crm/add'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_month_outlined),
                        title: const Text('Follow-up calendar'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/crm/calendar'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.people_outline),
                        title: const Text('My Leads'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/crm/leads'),
                      ),
                      const CrmQuizLinks(),
                    ],
                  ),
                ),
                const SizedBox(height: RvmSpacing.md),
                Text(
                  'Numbers stay masked until you tap Call. The server decides '
                  'who gets the next lead and when you may call.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: p.subtle, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  AppBar _bar(BuildContext context, String title) => AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () =>
                context.read<CrmHomeBloc>().add(const CrmHomeRefreshed()),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'My Leads',
            onPressed: () => context.push('/crm/leads'),
            icon: const Icon(Icons.people_outline),
          ),
          IconButton(
            tooltip: 'Add lead',
            onPressed: () => context.push('/crm/add'),
            icon: const Icon(Icons.person_add_alt_outlined),
          ),
        ],
      );

  Future<void> _startNext(BuildContext context, {CrmBucket? bucket}) async {
    try {
      final next = await crmRepository().next(bucket: bucket);
      if (!context.mounted) return;
      final lead = next.lead;
      if (lead == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No lead is waiting for you right now.')));
        return;
      }
      await startCrmCall(context,
          leadId: lead.id, origin: bucket == null ? 'dialer' : 'dialer');
    } catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$failure')));
    }
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.label,
    required this.value,
    required this.icon,
    this.danger = false,
    this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TeamCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: danger ? p.danger : p.primary),
          const SizedBox(height: 8),
          Text('$value',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: danger && value > 0 ? p.danger : null,
                  )),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontSize: 10.5, color: p.muted)),
        ],
      ),
    );
  }
}

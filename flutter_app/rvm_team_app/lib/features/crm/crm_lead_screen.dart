import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/crm_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import 'bloc/crm_blocs.dart';
import 'crm_shared.dart';

/// `/crm/lead/:id` — the lead and its timeline (team_app #51, item 7).
class CrmLeadScreen extends StatelessWidget {
  const CrmLeadScreen({super.key, required this.leadId});

  final int leadId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CrmLeadBloc(crmRepository(), leadId)
        ..add(const CrmLeadLoadRequested()),
      child: const _CrmLeadView(),
    );
  }
}

class _CrmLeadView extends StatelessWidget {
  const _CrmLeadView();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BlocConsumer<CrmLeadBloc, CrmLeadState>(
      listenWhen: (a, b) =>
          a.message != b.message || a.failure != b.failure,
      listener: (context, state) {
        final message = state.message;
        if (message != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
      },
      builder: (context, state) {
        final lead = state.lead;
        return Scaffold(
          backgroundColor: p.canvas,
          appBar: AppBar(
            title: const Text('Lead'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => context
                    .read<CrmLeadBloc>()
                    .add(const CrmLeadRefreshed()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: state.loading && lead == null
              ? const AppLoading(label: 'Loading the lead…')
              : state.failure != null && lead == null
                  ? crmFailure(state.failure,
                      onRetry: () => context
                          .read<CrmLeadBloc>()
                          .add(const CrmLeadRefreshed()))
                  : lead == null
                      ? const AppEmpty(
                          message: 'This lead is not available.',
                          icon: Icons.person_off_outlined)
                      : _LeadBody(lead: lead, state: state),
        );
      },
    );
  }
}

class _LeadBody extends StatelessWidget {
  const _LeadBody({required this.lead, required this.state});

  final CrmLeadDetail lead;
  final CrmLeadState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final summary = lead.summary;
    return RefreshIndicator(
      color: p.primary,
      onRefresh: () async =>
          context.read<CrmLeadBloc>().add(const CrmLeadRefreshed()),
      child: ListView(
        padding: const EdgeInsets.all(RvmSpacing.md),
        children: [
          TeamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TeamAvatar(name: summary.name, size: 48),
                    const SizedBox(width: RvmSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(summary.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            [summary.phoneMasked, summary.campaignName]
                                .where((v) => v.isNotEmpty)
                                .join(' · '),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: p.muted),
                          ),
                        ],
                      ),
                    ),
                    TeamPill(label: summary.stageName),
                  ],
                ),
                const SizedBox(height: RvmSpacing.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (summary.tagName != null)
                      TeamPill(label: summary.tagName!, dense: true),
                    if (summary.ownerName != null)
                      TeamPill(
                          label: 'Owner: ${summary.ownerName}', dense: true),
                    if (lead.whatsappOptOut)
                      TeamPill(
                          label: 'WhatsApp opted out',
                          tone: TeamPillTone.clay,
                          dense: true),
                    if (summary.attempts > 0)
                      TeamPill(
                          label: '${summary.attempts} attempts', dense: true),
                  ],
                ),
                if (summary.nextFollowupAt != null) ...[
                  const SizedBox(height: RvmSpacing.sm),
                  Row(
                    children: [
                      Icon(
                        summary.overdue
                            ? Icons.error_outline
                            : Icons.schedule,
                        size: 16,
                        color: summary.overdue ? p.danger : p.muted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Follow-up ${crmWhen(summary.nextFollowupAt!)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: summary.overdue ? p.danger : p.muted,
                              fontWeight: summary.overdue
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ],
                if (summary.latestRemark != null &&
                    summary.latestRemark!.isNotEmpty) ...[
                  const SizedBox(height: RvmSpacing.sm),
                  Text('“${summary.latestRemark}”',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
          const SizedBox(height: RvmSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: summary.stageKind.isFinal
                      ? null
                      : () => startCrmCall(context, leadId: lead.id),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: RvmSpacing.sm),
              if (lead.openCallId != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(
                        '/crm/lead/${lead.id}/dispose'
                        '?callId=${lead.openCallId}&origin=dialer'),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Finish form'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: RvmSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (state.templates.isNotEmpty && !lead.whatsappOptOut)
                OutlinedButton.icon(
                  onPressed: state.busy
                      ? null
                      : () => _whatsapp(context, state.templates),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                ),
              OutlinedButton.icon(
                onPressed:
                    state.busy ? null : () => _addReference(context, lead),
                icon: const Icon(Icons.person_add_alt_outlined),
                label: const Text('Add reference'),
              ),
              OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () => _transfer(context, summary.ownerName),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Transfer to me'),
              ),
            ],
          ),
          if (lead.properties.isNotEmpty) ...[
            const SizedBox(height: RvmSpacing.lg),
            TeamSectionHeader(title: 'Details'),
            const SizedBox(height: RvmSpacing.sm),
            TeamCard(
              child: Column(
                children: [
                  for (final entry in lead.properties.entries)
                    if (entry.value.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(entry.key,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: p.muted)),
                            ),
                            Expanded(
                              child: Text(entry.value,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ],
          const SizedBox(height: RvmSpacing.lg),
          TeamSectionHeader(title: 'Timeline', count: '${state.timeline.length}'),
          const SizedBox(height: RvmSpacing.sm),
          if (state.timeline.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No activity yet.'),
            )
          else
            for (final event in state.timeline)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(Icons.circle, size: 7, color: p.subtle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(event.label,
                              style: Theme.of(context).textTheme.bodyMedium),
                          Text(
                            [
                              if (event.at != null) crmWhen(event.at!),
                              if (event.actorName != null) event.actorName!,
                            ].join(' · '),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(fontSize: 10.5, color: p.subtle),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: RvmSpacing.lg),
        ],
      ),
    );
  }

  Future<void> _transfer(BuildContext context, String? owner) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Transfer to me?'),
        content: Text(owner == null
            ? 'This lead will become yours.'
            : 'This lead belongs to $owner. It will become yours.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Transfer')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<CrmLeadBloc>().add(const CrmLeadTransferRequested());
    }
  }

  Future<void> _addReference(BuildContext context, CrmLeadDetail lead) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add a reference'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Friend’s name')),
            const SizedBox(height: 10),
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                maxLength: 16,
                decoration: const InputDecoration(labelText: 'Phone number')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add')),
        ],
      ),
    );
    if (result == true && context.mounted) {
      context.read<CrmLeadBloc>().add(CrmLeadReferenceAdded(
          name: name.text.trim(), phone: phone.text.trim()));
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _whatsapp(
      BuildContext context, List<CrmWaTemplate> templates) async {
    final chosen = await showDialog<CrmWaTemplate>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('WhatsApp template'),
        children: [
          for (final template in templates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(template),
              child: ListTile(
                title: Text(template.name),
                subtitle: Text(template.preview ?? template.language),
              ),
            ),
        ],
      ),
    );
    if (chosen != null && context.mounted) {
      context.read<CrmLeadBloc>().add(CrmLeadWhatsappSent(chosen.id));
    }
  }
}

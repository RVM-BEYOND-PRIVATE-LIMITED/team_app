import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/crm_models.dart';
import '../../widgets/states.dart';
import 'bloc/crm_blocs.dart';
import 'crm_shared.dart';

/// `/crm/leads` — the five buckets with counts, each with View and Start
/// calling (team_app #51, item 5). A search sends the exact number in a
/// request body, never in a URL.
class CrmLeadsScreen extends StatelessWidget {
  const CrmLeadsScreen({super.key, this.initialBucket = CrmBucket.all});

  final CrmBucket initialBucket;

  @override
  Widget build(BuildContext context) {
    final bloc = CrmLeadsBloc(crmRepository())
      ..add(const CrmLeadsLoadRequested())
      ..add(CrmLeadsBucketSelected(initialBucket));
    return BlocProvider(
      create: (_) => bloc,
      child: const _CrmLeadsView(),
    );
  }
}

class _CrmLeadsView extends StatelessWidget {
  const _CrmLeadsView();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BlocBuilder<CrmLeadsBloc, CrmLeadsState>(
      builder: (context, state) {
        final leads = state.leads;
        return Scaffold(
          backgroundColor: p.canvas,
          appBar: AppBar(
            title: const Text('My Leads'),
            actions: [
              IconButton(
                tooltip: 'Find by number',
                onPressed: () => _lookup(context),
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () =>
                    context.read<CrmLeadsBloc>().add(const CrmLeadsRefreshed()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                    RvmSpacing.md, RvmSpacing.sm, RvmSpacing.md, 0),
                child: Row(
                  children: [
                    for (final bucket in CrmBucket.values) ...[
                      ChoiceChip(
                        selected: state.bucket == bucket,
                        onSelected: (_) => context
                            .read<CrmLeadsBloc>()
                            .add(CrmLeadsBucketSelected(bucket)),
                        label: Text(
                            '${bucket.label} (${state.count(bucket)})'),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(RvmSpacing.md),
                child: OutlinedButton.icon(
                  onPressed: () => _startBucket(context, state.bucket),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44)),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('Start calling · ${state.bucket.label}'),
                ),
              ),
              Expanded(
                child: state.loading && state.byBucket.isEmpty
                    ? const AppLoading(label: 'Loading your leads…')
                    : state.failure != null && state.byBucket.isEmpty
                        ? crmFailure(state.failure,
                            onRetry: () => context
                                .read<CrmLeadsBloc>()
                                .add(const CrmLeadsRefreshed()))
                        : leads.isEmpty
                            ? AppEmpty(
                                message:
                                    'No leads in ${state.bucket.label.toLowerCase()}.',
                                icon: Icons.people_outline)
                            : RefreshIndicator(
                                color: p.primary,
                                onRefresh: () async => context
                                    .read<CrmLeadsBloc>()
                                    .add(const CrmLeadsRefreshed()),
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                      RvmSpacing.md,
                                      0,
                                      RvmSpacing.md,
                                      RvmSpacing.lg),
                                  itemCount: leads.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: RvmSpacing.sm),
                                  itemBuilder: (_, index) {
                                    final lead = leads[index];
                                    return CrmLeadTile(
                                      lead: lead,
                                      onTap: () =>
                                          context.push('/crm/lead/${lead.id}'),
                                      onCall: () => startCrmCall(context,
                                          leadId: lead.id),
                                    );
                                  },
                                ),
                              ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startBucket(BuildContext context, CrmBucket bucket) async {
    try {
      final next = await crmRepository().next(bucket: bucket);
      if (!context.mounted) return;
      final lead = next.lead;
      if (lead == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No lead is waiting in ${bucket.label}.')));
        return;
      }
      await startCrmCall(context, leadId: lead.id);
    } on Failure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _lookup(BuildContext context) async {
    final phone = await showDialog<String>(
      context: context,
      builder: (_) => const _LookupDialog(),
    );
    if (phone == null || !context.mounted) return;
    try {
      final result = await crmRepository()
          .lookup(phone, idempotencyKey: 'lookup-${DateTime.now().microsecondsSinceEpoch}');
      if (!context.mounted) return;
      final lead = result.lead;
      if (lead == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No lead has that number.')));
        return;
      }
      if (result.ownerName != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('That lead belongs to ${result.ownerName}.')));
      }
      context.push('/crm/lead/${lead.id}');
    } on Failure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _LookupDialog extends StatefulWidget {
  const _LookupDialog();

  @override
  State<_LookupDialog> createState() => _LookupDialogState();
}

class _LookupDialogState extends State<_LookupDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Find by exact number'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          maxLength: 16,
          decoration: const InputDecoration(
            labelText: 'Full phone number',
            hintText: '10 digits',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = _controller.text.trim();
              if (value.length < 10) return;
              Navigator.of(context).pop(value);
            },
            child: const Text('Find'),
          ),
        ],
      );
}

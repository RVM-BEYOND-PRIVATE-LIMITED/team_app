import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/crm_models.dart';
import '../../widgets/states.dart';
import 'bloc/crm_blocs.dart';
import 'crm_shared.dart';

/// `/crm/add` — a walk-in or an enquiry (team_app #51, item 12). New number:
/// the lead is created and the form opens at once. A number already on file
/// shows its owner, with Log my call and Transfer to me.
class CrmAddLeadScreen extends StatefulWidget {
  const CrmAddLeadScreen({super.key});

  @override
  State<CrmAddLeadScreen> createState() => _CrmAddLeadScreenState();
}

class _CrmAddLeadScreenState extends State<CrmAddLeadScreen> {
  bool _loading = true;
  Failure? _failure;
  CrmSetup? _setup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final setup = await crmRepository().setup();
      if (!mounted) return;
      setState(() {
        _setup = setup;
        _loading = false;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_loading) {
      return const Scaffold(body: AppLoading(label: 'Loading the form…'));
    }
    if (_failure != null || _setup == null) {
      return Scaffold(
        backgroundColor: p.canvas,
        appBar: AppBar(title: const Text('Add a lead')),
        body: crmFailure(_failure, onRetry: _load),
      );
    }
    return BlocProvider(
      create: (_) =>
          CrmAddLeadBloc(crmRepository(), _setup!)..add(
        CrmAddLeadCampaign(_setup!.campaigns.isEmpty
            ? 0
            : _setup!.campaigns.first.id),
      ),
      child: _AddLeadForm(setup: _setup!),
    );
  }
}

class _AddLeadForm extends StatefulWidget {
  const _AddLeadForm({required this.setup});
  final CrmSetup setup;

  @override
  State<_AddLeadForm> createState() => _AddLeadFormState();
}

class _AddLeadFormState extends State<_AddLeadForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _alt = TextEditingController();
  bool _handled = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _alt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BlocConsumer<CrmAddLeadBloc, CrmAddLeadState>(
      listenWhen: (a, b) => a.result != b.result || a.failure != b.failure,
      listener: (context, state) {
        final result = state.result;
        if (result != null && !_handled) {
          _handled = true;
          _onResult(context, result);
        }
      },
      builder: (context, state) {
        final campaigns = widget.setup.campaigns;
        return Scaffold(
          backgroundColor: p.canvas,
          appBar: AppBar(title: const Text('Add a lead')),
          body: ListView(
            padding: const EdgeInsets.all(RvmSpacing.md),
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                maxLength: 16,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '10 digits',
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _alt,
                keyboardType: TextInputType.phone,
                maxLength: 16,
                decoration: const InputDecoration(
                    labelText: 'Alternate number (optional)'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: state.source,
                decoration: const InputDecoration(labelText: 'Source'),
                items: const [
                  DropdownMenuItem(value: 'manual', child: Text('Walk-in')),
                  DropdownMenuItem(value: 'ivr', child: Text('Inbound call')),
                  DropdownMenuItem(value: 'referral', child: Text('Referral')),
                ],
                onChanged: (source) {
                  if (source != null) {
                    context
                        .read<CrmAddLeadBloc>()
                        .add(CrmAddLeadSource(source));
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: state.campaignId,
                decoration: const InputDecoration(labelText: 'Campaign'),
                items: [
                  for (final campaign in campaigns)
                    DropdownMenuItem(
                        value: campaign.id,
                        child: Text(campaign.name,
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) {
                  if (id != null) {
                    context
                        .read<CrmAddLeadBloc>()
                        .add(CrmAddLeadCampaign(id));
                  }
                },
              ),
              if (state.failure != null) ...[
                const SizedBox(height: RvmSpacing.md),
                Text(state.failure!.message,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: p.danger)),
              ],
              const SizedBox(height: RvmSpacing.lg),
              FilledButton.icon(
                onPressed: state.submitting
                    ? null
                    : () => _submit(context),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                icon: state.submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.person_add_alt_outlined),
                label: Text(state.submitting ? 'Saving…' : 'Add and call'),
              ),
              const SizedBox(height: RvmSpacing.md),
              Text(
                'One lead per number. If the number is already on file, you '
                'will see its owner instead of a second lead.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: p.subtle, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  void _submit(BuildContext context) {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a name.')));
      return;
    }
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the full ten-digit number.')));
      return;
    }
    context.read<CrmAddLeadBloc>().add(CrmAddLeadSubmit(
          name: name,
          phone: phone,
          altPhone: _alt.text.trim().isEmpty ? null : _alt.text.trim(),
        ));
  }

  Future<void> _onResult(BuildContext context, CrmAddLeadResult result) async {
    final lead = result.lead;
    if (lead == null) {
      context.go('/crm');
      return;
    }
    if (result.callId != null) {
      context.pushReplacement(
          '/crm/lead/${lead.id}/dispose?callId=${result.callId}'
          '&origin=manual${result.existed ? '' : ''}');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(lead.summary.name),
              subtitle: Text(
                  'Already on file${result.ownerName == null ? '' : ' · ${result.ownerName}'}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('Log my call'),
              onTap: () {
                Navigator.of(sheet).pop();
                startCrmCall(context, leadId: lead.id, origin: 'manual');
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Transfer to me'),
              onTap: () async {
                Navigator.of(sheet).pop();
                try {
                  await crmRepository().transferToMe(lead.id,
                      idempotencyKey:
                          IdempotencyInterceptor.newKey());
                  if (context.mounted) context.push('/crm/lead/${lead.id}');
                } on Failure catch (failure) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(failure.message)));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open the lead'),
              onTap: () {
                Navigator.of(sheet).pop();
                context.push('/crm/lead/${lead.id}');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

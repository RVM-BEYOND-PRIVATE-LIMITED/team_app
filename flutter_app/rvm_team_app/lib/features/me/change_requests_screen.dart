import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

/// Phase 2C, E3: ask HR to correct date of birth, address or legal name. HR applies it in the
/// Scheduler; the request is the paper trail.
class ChangeRequestsScreen extends StatefulWidget {
  const ChangeRequestsScreen({super.key});

  @override
  State<ChangeRequestsScreen> createState() => _ChangeRequestsScreenState();
}

class _ChangeRequestsScreenState extends State<ChangeRequestsScreen> {
  bool _loading = true;
  Failure? _failure;
  List<ChangeRequest> _requests = const [];

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
      final list = await getIt<EssRepository>().myChangeRequests();
      if (!mounted) return;
      setState(() {
        _requests = list;
        _loading = false;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _failure = f;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final created = await showDialog<ChangeRequest>(
      context: context,
      builder: (_) => const _NewChangeDialog(),
    );
    if (created != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Profile changes',
            subtitle: const Text('Ask HR to correct your record'),
            actions: [
              TeamHeaderAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh',
                  onPressed: _load)
            ],
          ),
          Expanded(child: _body()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New request'),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) {
      return AppError(message: _failure!.message, onRetry: _load);
    }
    if (_requests.isEmpty) {
      return const AppEmpty(
          icon: Icons.edit_note, message: 'No change requests yet.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
            RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, 96),
        itemCount: _requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.md),
        itemBuilder: (context, i) {
          final r = _requests[i];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(RvmSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(r.fieldLabel,
                              style: Theme.of(context).textTheme.titleMedium)),
                      Text(r.status,
                          style: Theme.of(context).textTheme.labelMedium),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (r.oldValue != null) Text('From: ${r.oldValue}'),
                  Text('To: ${r.newValue}'),
                  Text(r.reason, style: Theme.of(context).textTheme.bodySmall),
                  if (r.decisionNote != null)
                    Text(
                        'HR: ${r.decisionNote}${r.decidedByName != null ? ' — ${r.decidedByName}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NewChangeDialog extends StatefulWidget {
  const _NewChangeDialog();

  @override
  State<_NewChangeDialog> createState() => _NewChangeDialogState();
}

class _NewChangeDialogState extends State<_NewChangeDialog> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _reason = TextEditingController();
  String _field = 'date_of_birth';
  bool _saving = false;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newValue = _new.text.trim();
    final reason = _reason.text.trim();
    if (newValue.isEmpty || reason.length < 5) return;
    setState(() => _saving = true);
    try {
      final created = await getIt<EssRepository>().createChangeRequest(
        field: _field,
        oldValue: _old.text.trim().isEmpty ? null : _old.text.trim(),
        newValue: newValue,
        reason: reason,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request a change'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _field,
              decoration: const InputDecoration(labelText: 'Field'),
              items: const [
                DropdownMenuItem(
                    value: 'date_of_birth', child: Text('Date of birth')),
                DropdownMenuItem(value: 'address', child: Text('Address')),
                DropdownMenuItem(
                    value: 'legal_name', child: Text('Legal name')),
              ],
              onChanged: (v) => setState(() => _field = v ?? _field),
            ),
            const SizedBox(height: 8),
            TextField(
                controller: _old,
                decoration: const InputDecoration(
                    labelText: 'Current value (optional)')),
            const SizedBox(height: 8),
            TextField(
                controller: _new,
                decoration: const InputDecoration(labelText: 'Correct value')),
            const SizedBox(height: 8),
            TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Reason')),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _saving ? null : _submit, child: const Text('Send')),
      ],
    );
  }
}

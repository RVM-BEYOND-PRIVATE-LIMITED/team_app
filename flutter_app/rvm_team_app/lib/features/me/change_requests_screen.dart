import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../app_validators.dart';
import '../../data/repositories/ess_repository.dart';
import '../../app_feedback.dart';
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
    if (_loading && _requests.isEmpty) return const AppLoading();
    if (_failure != null && _requests.isEmpty) {
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
    final reason = _reason.text.trim();
    var newValue = _new.text.trim();
    if (_field == 'date_of_birth') {
      if (!isValidDob(newValue)) {
        showAppMessage('Pick your date of birth from the calendar.');
        return;
      }
    } else if (newValue.isEmpty) {
      showAppMessage('Enter the correct value.');
      return;
    }
    if (reason.length < 5) {
      showAppMessage('Give a reason (at least 5 characters).');
      return;
    }
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
      showAppMessage(f.message);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = isValidIsoDate(_new.text.trim())
        ? DateTime.parse(_new.text.trim())
        : DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? DateTime(now.year - 18) : initial,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null) setState(() => _new.text = toIsoDate(picked));
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
              onChanged: (v) {
                if (v != null) setState(() => _field = v);
              },
            ),
            const SizedBox(height: 8),
            TextField(
                controller: _old,
                decoration: const InputDecoration(
                    labelText: 'Current value (optional)')),
            const SizedBox(height: 8),
            if (_field == 'date_of_birth')
              TextField(
                controller: _new,
                readOnly: true,
                onTap: _pickDob,
                decoration: const InputDecoration(
                  labelText: 'Correct date of birth',
                  hintText: 'Pick from the calendar',
                  prefixIcon: Icon(Icons.cake_outlined),
                ),
              )
            else
              TextField(
                  controller: _new,
                  decoration:
                      const InputDecoration(labelText: 'Correct value')),
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

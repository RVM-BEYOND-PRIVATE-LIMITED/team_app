import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

/// E3/E5: HR's queue of profile-change requests. Deciding records the answer only; HR applies the
/// change in the Scheduler. Backend: `GET /api/ess/hr/change-requests`, `POST .../decide`.
class HrChangeRequestsScreen extends StatefulWidget {
  const HrChangeRequestsScreen({super.key});

  @override
  State<HrChangeRequestsScreen> createState() => _HrChangeRequestsScreenState();
}

class _HrChangeRequestsScreenState extends State<HrChangeRequestsScreen> {
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
      final list = await getIt<EssRepository>().hrChangeRequests();
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

  Future<void> _decide(ChangeRequest r, bool approve) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve change' : 'Reject change'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
              hintText: approve ? 'Note (optional)' : 'Reason (required)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(approve ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (note == null || !mounted) return;
    if (!approve && note.length < 3) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('A rejection needs a reason.')));
      return;
    }
    try {
      await getIt<EssRepository>()
          .decideChangeRequest(r.id, approve: approve, note: note);
      await _load();
    } on Failure catch (f) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(f.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Profile changes',
            subtitle: const Text('HR review queue'),
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
    );
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) {
      return AppError(message: _failure!.message, onRetry: _load);
    }
    if (_requests.isEmpty) {
      return const AppEmpty(
          icon: Icons.edit_note, message: 'No change requests.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(RvmSpacing.md),
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
                  if (r.status == 'pending') ...[
                    const SizedBox(height: RvmSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                            child: FilledButton(
                                onPressed: () => _decide(r, true),
                                child: const Text('Approve'))),
                        const SizedBox(width: RvmSpacing.sm),
                        Expanded(
                            child: OutlinedButton(
                                onPressed: () => _decide(r, false),
                                child: const Text('Reject'))),
                      ],
                    ),
                  ],
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

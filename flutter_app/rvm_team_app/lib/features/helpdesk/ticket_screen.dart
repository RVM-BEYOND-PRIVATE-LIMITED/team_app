import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

/// One ticket with its thread (G2/G5).
class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.ticketId});
  final String ticketId;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  final _comment = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  Failure? _failure;
  HelpdeskTicketDetail? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await getIt<EssRepository>().ticket(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _failure = null;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _failure = f;
        _loading = false;
      });
    }
  }

  Future<void> _act(String action, {Map<String, dynamic>? data}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await getIt<EssRepository>()
          .ticketAction(widget.ticketId, action, data: data);
      await _load();
    } on Failure catch (f) {
      _snack(f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _comment_() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await getIt<EssRepository>()
          .addTicketComment(id: widget.ticketId, body: text);
      _comment.clear();
      await _load();
    } on Failure catch (f) {
      _snack(f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final result = await showDialog<({String reason, int? rating})>(
      context: context,
      builder: (_) => const _CloseDialog(),
    );
    if (result == null || !mounted) return;
    await _act('close', data: {
      'closing_reason': result.reason,
      if (result.rating != null) 'rating': result.rating,
    });
  }

  Future<void> _assign() async {
    final person = await showDialog<OrgCard>(
        context: context, builder: (_) => const _AssignDialog());
    if (person == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await getIt<EssRepository>()
          .assignTicket(id: widget.ticketId, employeeId: person.id);
      await _load();
    } on Failure catch (f) {
      _snack(f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final ticket = _detail?.ticket;
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: ticket == null ? 'Ticket' : ticket.ref,
            subtitle: Text(ticket?.category.name ?? 'Support ticket'),
            actions: [
              IconButton(
                  tooltip: 'Assign',
                  onPressed: _busy ? null : _assign,
                  icon: const Icon(Icons.person_add_alt)),
            ],
          ),
          Expanded(child: _body()),
          if (ticket != null && ticket.isOpen)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _comment,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            hintText: 'Write a message…',
                            border: OutlineInputBorder(),
                            isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        onPressed: _busy ? null : _comment_,
                        icon: const Icon(Icons.send)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) {
      return AppError(message: _failure!.message, onRetry: _load);
    }
    final detail = _detail!;
    final t = detail.ticket;
    return ListView(
      padding: const EdgeInsets.all(RvmSpacing.md),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(RvmSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.subject, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                    '${t.category.name} · ${t.status.replaceAll('_', ' ')} · ${t.priority ?? ''}'),
                if (t.assignee != null)
                  Text('With ${t.assignee!.fullName}',
                      style: Theme.of(context).textTheme.bodySmall),
                if (t.infra != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Infra register'
                    '${t.infra!.ticketNo != null ? ' #${t.infra!.ticketNo}' : ''}'
                    ' · ${t.infra!.status}'
                    '${t.infra!.closedOn != null ? ' since ${t.infra!.closedOn!.toLocal().toString().split(' ').first}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (t.overdue)
                  Text('Overdue by ${t.overdueMinutes} working minutes',
                      style: const TextStyle(color: RvmColors.danger)),
                if (t.body != null) ...[
                  const SizedBox(height: RvmSpacing.sm),
                  Text(t.body!),
                ],
                const SizedBox(height: RvmSpacing.sm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (t.isOpen && t.assignee == null)
                      FilledButton.tonal(
                          onPressed: _busy ? null : () => _act('claim'),
                          child: const Text('Claim')),
                    if (t.isOpen)
                      OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _act('status',
                                  data: {'status': 'in_progress'}),
                          child: const Text('In progress')),
                    if (t.isOpen)
                      OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () =>
                                  _act('status', data: {'status': 'resolved'}),
                          child: const Text('Resolved')),
                    if (t.status == 'resolved')
                      OutlinedButton(
                          onPressed: _busy ? null : () => _act('reopen'),
                          child: const Text('Reopen')),
                    if (t.status == 'open' && t.mine)
                      OutlinedButton(
                          onPressed: _busy ? null : () => _act('withdraw'),
                          child: const Text('Withdraw')),
                    if (t.mine || t.status == 'resolved')
                      OutlinedButton(
                          onPressed: _busy ? null : _close,
                          child: const Text('Close')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RvmSpacing.md),
        Text('Thread', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: RvmSpacing.sm),
        for (final m in detail.messages) _MessageTile(message: m),
      ],
    );
  }
}

class _CloseDialog extends StatefulWidget {
  const _CloseDialog();

  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  final _reason = TextEditingController();
  int? _rating;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Close the ticket'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'Reason (at least 3 characters)'),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () =>
                      setState(() => _rating = _rating == i ? null : i),
                  icon: Icon(
                      i <= (_rating ?? 0) ? Icons.star : Icons.star_border,
                      color: RvmColors.warning),
                ),
            ],
          ),
          const Text('Optional rating', style: TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final reason = _reason.text.trim();
            if (reason.length < 3) return;
            Navigator.pop(context, (reason: reason, rating: _rating));
          },
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _AssignDialog extends StatefulWidget {
  const _AssignDialog();

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  final _query = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<OrgCard> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _run(value.trim()));
  }

  Future<void> _run(String q) async {
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _loading = true);
    try {
      final page = await getIt<EssRepository>().directory(query: q);
      if (!mounted) return;
      setState(() {
        _results = page.people;
        _loading = false;
      });
    } on Failure {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign ticket'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search a colleague'),
            ),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator()),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in _results.take(8))
                    ListTile(
                      leading: CircleAvatar(
                          child: Text(p.fullName.isEmpty
                              ? '?'
                              : p.fullName.substring(0, 1).toUpperCase())),
                      title: Text(p.fullName),
                      subtitle: Text(p.designation ?? p.employeeCode ?? ''),
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'))
      ],
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});
  final HelpdeskMessage message;

  @override
  Widget build(BuildContext context) {
    final event = message.kind == 'event';
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: event ? scheme.surfaceContainerHighest : scheme.surface,
          borderRadius: BorderRadius.circular(RvmRadii.sm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                event
                    ? _eventLabel(message.event)
                    : (message.author?.fullName ?? 'Someone'),
                style: Theme.of(context).textTheme.labelMedium),
            if (message.body != null) ...[
              const SizedBox(height: 4),
              Text(message.body!)
            ],
          ],
        ),
      ),
    );
  }

  static String _eventLabel(String? event) => switch (event) {
        'opened' => 'Ticket opened',
        'claimed' => 'Ticket claimed',
        'status_changed' => 'Status changed',
        'closed' => 'Ticket closed',
        'reopened' => 'Ticket reopened',
        'withdrawn' => 'Ticket withdrawn',
        'assigned' => 'Ticket assigned',
        _ => (event ?? 'Update').replaceAll('_', ' '),
      };
}

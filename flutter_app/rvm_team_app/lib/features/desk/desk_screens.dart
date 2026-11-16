import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../domain/team_stage2_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import '../stage2/stage2_shared.dart';

/// `/desk` — the student desk queues (#56).
class DeskHomeScreen extends StatefulWidget {
  const DeskHomeScreen({super.key});
  @override
  State<DeskHomeScreen> createState() => _DeskHomeScreenState();
}

class _DeskHomeScreenState extends State<DeskHomeScreen> {
  Future<List<DeskQueue>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().deskCounts());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Student desk'),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<List<DeskQueue>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return stage2Failure(
                snapshot.error is Failure ? snapshot.error as Failure : null,
                onRetry: _load);
          }
          final counts = snapshot.data ?? const [];
          if (counts.isEmpty) return stage2Empty('Nothing in the desk queues.');
          return ListView.separated(
            padding: const EdgeInsets.all(RvmSpacing.md),
            itemCount: counts.length,
            separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
            itemBuilder: (_, i) {
              final q = counts[i];
              return TeamCard(
                onTap: q.available ? () => _open(q.key) : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(q.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          if (!q.available)
                            Text('Not available yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: p.muted)),
                        ],
                      ),
                    ),
                    Text('${q.count}',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _open(String key) {
    switch (key) {
      case 'paid_number_not_linked':
      case 'number_not_linked':
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LinkPhoneScreen()));
      case 'phone_change_requests':
      case 'phone_changes':
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PhoneChangesScreen()));
      case 'extra_view_requests':
      case 'view_requests':
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ViewRequestsScreen()));
      default:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('This queue opens on the Scheduler web.')));
    }
  }
}

/// `/desk/link` — find an admission and link the student's number (#56 item 3).
class LinkPhoneScreen extends StatefulWidget {
  const LinkPhoneScreen({super.key});
  @override
  State<LinkPhoneScreen> createState() => _LinkPhoneScreenState();
}

class _LinkPhoneScreenState extends State<LinkPhoneScreen> {
  final _search = TextEditingController();
  final _phone = TextEditingController();
  final _phone2 = TextEditingController();
  List<LinkCandidate>? _candidates;
  LinkCandidate? _picked;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    _phone.dispose();
    _phone2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Link a phone')),
      body: ListView(
        padding: const EdgeInsets.all(RvmSpacing.md),
        children: [
          TextField(
            controller: _search,
            decoration: const InputDecoration(
                labelText: 'Name, admission number or phone'),
            onSubmitted: (_) => _find(),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _find, child: const Text('Find admission')),
          if (_candidates != null) ...[
            const SizedBox(height: RvmSpacing.md),
            for (final c in _candidates!)
              ListTile(
                onTap: () => setState(() => _picked = c),
                leading: Icon(_picked == c
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(c.name),
                subtitle: Text(
                    '${c.admissionNumber} · ${c.course}${c.batch.isEmpty ? '' : ' · ${c.batch}'}'
                    '${c.phoneMasked == null ? '' : ' · ${c.phoneMasked}'}'),
              ),
          ],
          const SizedBox(height: RvmSpacing.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: 16,
            decoration: const InputDecoration(labelText: 'Student number'),
          ),
          TextField(
            controller: _phone2,
            keyboardType: TextInputType.phone,
            maxLength: 16,
            decoration: const InputDecoration(labelText: 'Enter it again'),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: p.danger)),
          const SizedBox(height: RvmSpacing.md),
          FilledButton(
            onPressed: _busy || _picked == null ? null : _link,
            child: Text(_busy ? 'Linking…' : 'Link this phone'),
          ),
        ],
      ),
    );
  }

  Future<void> _find() async {
    try {
      final rows = await stage2Repository().linkCandidates(_search.text.trim());
      if (mounted) setState(() => _candidates = rows);
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    }
  }

  Future<void> _link() async {
    final a = _phone.text.trim();
    final b = _phone2.text.trim();
    if (a.length < 10) {
      setState(() => _error = 'Enter the full ten-digit number.');
      return;
    }
    if (a != b) {
      setState(() => _error = 'The two numbers do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await stage2Repository().linkStudent(
          admissionId: _picked!.studentId,
          phone: a,
          reason: 'Linked from the Team app',
          key: 'link-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone linked.')));
        Navigator.of(context).pop();
      }
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// `/desk/phone-changes` — approve or refuse with a note (#56 item 4).
class PhoneChangesScreen extends StatefulWidget {
  const PhoneChangesScreen({super.key});
  @override
  State<PhoneChangesScreen> createState() => _PhoneChangesScreenState();
}

class _PhoneChangesScreenState extends State<PhoneChangesScreen> {
  Future<List<PhoneChangeRequest>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().phoneChanges());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Phone changes')),
        body: FutureBuilder<List<PhoneChangeRequest>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoading();
            }
            if (snapshot.hasError) {
              return stage2Failure(
                  snapshot.error is Failure ? snapshot.error as Failure : null,
                  onRetry: _load);
            }
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) return stage2Empty('No phone change requests.');
            return ListView.separated(
              padding: const EdgeInsets.all(RvmSpacing.md),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
              itemBuilder: (_, i) {
                final r = rows[i];
                return TeamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.studentName,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${r.oldMasked ?? 'old'} → ${r.newMasked ?? 'new number'}'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton(
                              onPressed: () => _decide(r, true),
                              child: const Text('Approve')),
                          const SizedBox(width: 8),
                          OutlinedButton(
                              onPressed: () => _decide(r, false),
                              child: const Text('Refuse')),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );

  Future<void> _decide(PhoneChangeRequest r, bool approve) async {
    final reason = await _note(context, approve: approve);
    if (reason == null) return;
    try {
      await stage2Repository().decidePhoneChange(r.id,
          approve: approve,
          reason: reason,
          key: 'phone-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) _load();
    } on Failure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  Future<String?> _note(BuildContext context, {required bool approve}) async {
    final controller = TextEditingController();
    final out = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(approve ? 'Approve with a note' : 'Why refuse?'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Note')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(approve ? 'Approve' : 'Refuse')),
        ],
      ),
    );
    controller.dispose();
    return out != null && out.length >= 3 ? out : null;
  }
}

/// `/desk/views` — extra video views (#56 item 5).
class ViewRequestsScreen extends StatefulWidget {
  const ViewRequestsScreen({super.key});
  @override
  State<ViewRequestsScreen> createState() => _ViewRequestsScreenState();
}

class _ViewRequestsScreenState extends State<ViewRequestsScreen> {
  Future<List<ViewRequest>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().viewRequests());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Extra views')),
        body: FutureBuilder<List<ViewRequest>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoading();
            }
            if (snapshot.hasError) {
              return stage2Failure(
                  snapshot.error is Failure ? snapshot.error as Failure : null,
                  onRetry: _load);
            }
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) return stage2Empty('No extra view requests.');
            return ListView.separated(
              padding: const EdgeInsets.all(RvmSpacing.md),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
              itemBuilder: (_, i) {
                final r = rows[i];
                return TeamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.studentName,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${r.videoTitle} · ${r.viewsUsed} views used'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton(
                              onPressed: () => _decide(r, true),
                              child: const Text('Grant one')),
                          const SizedBox(width: 8),
                          OutlinedButton(
                              onPressed: () => _decide(r, false),
                              child: const Text('Refuse')),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );

  Future<void> _decide(ViewRequest r, bool grant) async {
    try {
      await stage2Repository().decideViewRequest(r.id,
          grant: grant,
          note: grant ? 'Granted from the Team app' : 'Refused in the Team app',
          key: 'view-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) _load();
    } on Failure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }
}

import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

/// G5: the team queue — the tickets of the categories the caller's role serves.
class HelpdeskQueueScreen extends StatefulWidget {
  const HelpdeskQueueScreen({super.key});

  @override
  State<HelpdeskQueueScreen> createState() => _HelpdeskQueueScreenState();
}

class _HelpdeskQueueScreenState extends State<HelpdeskQueueScreen> {
  bool _loading = true;
  Failure? _failure;
  HelpdeskQueue? _queue;

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
      final queue = await getIt<EssRepository>().helpdeskQueue();
      if (!mounted) return;
      setState(() {
        _queue = queue;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Team queue',
            subtitle: const Text('Tickets your role serves'),
            actions: [
              TeamHeaderAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh',
                  onPressed: _load),
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
    final queue = _queue;
    if (queue == null || queue.tickets.isEmpty) {
      return const AppEmpty(
          icon: Icons.inbox_outlined, message: 'The queue is empty.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(RvmSpacing.md),
        itemCount: queue.tickets.length,
        separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
        itemBuilder: (context, i) {
          final t = queue.tickets[i];
          return Card(
            child: ListTile(
              onTap: () => context.push('/helpdesk/ticket/${t.id}'),
              title: Text('${t.ref} · ${t.subject}',
                  overflow: TextOverflow.ellipsis),
              subtitle: Text([
                t.category.name,
                t.status.replaceAll('_', ' '),
                if (t.assignee != null) 'with ${t.assignee!.fullName}',
                if (t.overdue) 'overdue',
              ].where((s) => s.isNotEmpty).join(' · ')),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        },
      ),
    );
  }
}

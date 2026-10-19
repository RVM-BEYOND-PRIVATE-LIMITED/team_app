import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

/// F5/F7/F8: HR's Wall desk — the reports queue, the sender's announcements with their counts, and
/// the moderation log. Backend: `/api/ess/wall/hr/*` and `/wall/announcements`.
class WallModerationScreen extends StatefulWidget {
  const WallModerationScreen({super.key});

  @override
  State<WallModerationScreen> createState() => _WallModerationScreenState();
}

class _WallModerationScreenState extends State<WallModerationScreen> {
  bool _loading = true;
  Failure? _failure;
  List<WallReport> _reports = const [];
  List<WallAnnouncement> _announcements = const [];
  List<ModerationEntry> _log = const [];

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
      final repo = getIt<EssRepository>();
      final reports = await repo.wallReports();
      List<WallAnnouncement> announcements = const [];
      List<ModerationEntry> log = const [];
      try {
        announcements = await repo.hrAnnouncements();
      } on Failure {
        // Not an announcer: the reports still work.
      }
      try {
        log = await repo.moderationLog();
      } on Failure {
        // Ignore.
      }
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _announcements = announcements;
        _log = log;
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

  Future<void> _resolve(WallReport report, bool hidden) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(hidden ? 'Hide this content' : 'Keep this content'),
        content: TextField(controller: controller, minLines: 2, maxLines: 3, decoration: const InputDecoration(hintText: 'Note (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: Text(hidden ? 'Hide' : 'Keep')),
        ],
      ),
    );
    if (note == null || !mounted) return;
    try {
      await getIt<EssRepository>().resolveReport(report.id, hidden: hidden, note: note);
      await _load();
    } on Failure catch (f) {
      _snack(f.message);
    }
  }

  Future<void> _counts(WallAnnouncement a) async {
    try {
      final counts = await getIt<EssRepository>().announcementCounts(a.id);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(a.title),
          content: Text(counts.entries.map((e) => '${e.key}: ${e.value}').join('\n')),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
        ),
      );
    } on Failure catch (f) {
      _snack(f.message);
    }
  }

  Future<void> _compose() async {
    final created = await showDialog<bool>(context: context, builder: (_) => const _AnnouncementComposer());
    if (created == true) await _load();
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Wall desk',
            subtitle: const Text('Reports, announcements and the log'),
            actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
          Expanded(child: _body()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('Announcement'),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) return AppError(message: _failure!.message, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, 96),
        children: [
          Text('Open reports (${_reports.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: RvmSpacing.sm),
          if (_reports.isEmpty)
            const Text('No open reports.')
          else
            for (final r in _reports) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(RvmSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r.target} · ${r.reason}', style: Theme.of(context).textTheme.titleSmall),
                      if (r.targetPreview != null) Text('“${r.targetPreview}”'),
                      Text('by ${r.reporter?.fullName ?? 'someone'}', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: RvmSpacing.sm),
                      Row(
                        children: [
                          Expanded(child: FilledButton(onPressed: () => _resolve(r, true), child: const Text('Hide content'))),
                          const SizedBox(width: RvmSpacing.sm),
                          Expanded(child: OutlinedButton(onPressed: () => _resolve(r, false), child: const Text('Keep'))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: RvmSpacing.sm),
            ],
          const SizedBox(height: RvmSpacing.md),
          Text('My announcements', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: RvmSpacing.sm),
          if (_announcements.isEmpty)
            const Text('No announcements yet.')
          else
            for (final a in _announcements)
              Card(
                child: ListTile(
                  title: Text(a.title),
                  subtitle: Text(a.needsAck ? 'Needs acknowledgement' : 'Read-only'),
                  trailing: TextButton(onPressed: () => _counts(a), child: const Text('Counts')),
                ),
              ),
          const SizedBox(height: RvmSpacing.md),
          Text('Moderation log', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: RvmSpacing.sm),
          if (_log.isEmpty)
            const Text('Nothing logged.')
          else
            for (final e in _log.take(20))
              ListTile(
                dense: true,
                title: Text(e.action.replaceAll('.', ' · ').replaceAll('_', ' ')),
                subtitle: Text([e.actorName, e.at?.toLocal().toString().split('.').first].whereType<String>().join(' · ')),
              ),
        ],
      ),
    );
  }
}

class _AnnouncementComposer extends StatefulWidget {
  const _AnnouncementComposer();

  @override
  State<_AnnouncementComposer> createState() => _AnnouncementComposerState();
}

class _AnnouncementComposerState extends State<_AnnouncementComposer> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _needsAck = false;
  bool _pinned = false;
  DateTime _closes = DateTime.now().add(const Duration(days: 7));
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  String get _closesIso =>
      '${_closes.year.toString().padLeft(4, '0')}-${_closes.month.toString().padLeft(2, '0')}-${_closes.day.toString().padLeft(2, '0')}';

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _closes,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _closes = picked);
  }

  Future<void> _save() async {
    if (_title.text.trim().length < 3 || _body.text.trim().length < 3) return;
    setState(() => _saving = true);
    try {
      await getIt<EssRepository>().createAnnouncement(
        title: _title.text.trim(),
        body: _body.text.trim(),
        needsAck: _needsAck,
        closesOn: _needsAck ? _closesIso : null,
        pinned: _pinned,
      );
      if (mounted) Navigator.pop(context, true);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New announcement'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _title, maxLength: 200, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: _body, minLines: 3, maxLines: 8, maxLength: 5000, decoration: const InputDecoration(labelText: 'Message')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _needsAck,
              onChanged: (v) => setState(() => _needsAck = v),
              title: const Text('Needs acknowledgement'),
            ),
            if (_needsAck)
              OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.event), label: Text('Closes: $_closesIso')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
              title: const Text('Pin to the top'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Publish')),
      ],
    );
  }
}

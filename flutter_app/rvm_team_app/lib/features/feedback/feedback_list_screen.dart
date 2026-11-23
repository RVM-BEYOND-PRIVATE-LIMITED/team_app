import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import '../../widgets/team_kit.dart';

/// The super admins' in-app feedback list (#153, backend #151).
class FeedbackListScreen extends StatefulWidget {
  const FeedbackListScreen({super.key});

  @override
  State<FeedbackListScreen> createState() => _FeedbackListScreenState();
}

class _FeedbackListScreenState extends State<FeedbackListScreen> {
  final _scroll = ScrollController();
  final List<AppFeedbackEntry> _items = [];
  AppFeedbackKind? _kind;
  String? _next;
  bool _loading = true;
  bool _loadingMore = false;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || _next == null) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _failure = null;
        _items.clear();
        _next = null;
      });
    } else {
      if (_loadingMore || _next == null) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = await getIt<EssRepository>()
          .feedbackPage(kind: _kind, before: reset ? null : _next);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _next = page.nextBefore;
      });
    } on Failure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } catch (_) {
      if (mounted) setState(() => _failure = const UnknownFailure());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _select(AppFeedbackKind? kind) {
    if (kind == _kind) return;
    setState(() => _kind = kind);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      body: Column(
        children: [
          TeamPageHeader(
            title: 'App feedback',
            subtitle: const Text('Bugs and suggestions from staff'),
            actions: [
              TeamHeaderAction(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onPressed: () => _load(reset: true),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RvmSpacing.md,
              RvmSpacing.sm,
              RvmSpacing.md,
              0,
            ),
            child: TeamSegmentedTabs(
              labels: const ['All', 'Bug', 'Suggestion', 'Other'],
              selectedIndex: _kind == null ? 0 : _kind!.index + 1,
              onChanged: (i) => _select(
                i == 0 ? null : AppFeedbackKind.values[i - 1],
              ),
            ),
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const AppLoading(label: 'Loading feedback…');
    }
    if (_failure != null && _items.isEmpty) {
      return AppError(
        message: _failure!.message,
        onRetry: () => _load(reset: true),
      );
    }
    if (_items.isEmpty) {
      return const AppEmpty(
        icon: Icons.feedback_outlined,
        message: 'No feedback yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.all(RvmSpacing.md),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
        itemBuilder: (context, i) {
          if (i == _items.length) {
            return const Padding(
              padding: EdgeInsets.all(RvmSpacing.md),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _FeedbackCard(entry: _items[i]);
        },
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.entry});

  final AppFeedbackEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return TeamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TeamPill(
                label: entry.kind.label,
                tone: switch (entry.kind) {
                  AppFeedbackKind.bug => TeamPillTone.danger,
                  AppFeedbackKind.suggestion => TeamPillTone.success,
                  AppFeedbackKind.other => TeamPillTone.warning,
                },
                dense: true,
              ),
              const Spacer(),
              Text(
                _when(entry.createdAt),
                style: text.labelSmall?.copyWith(color: p.subtle),
              ),
            ],
          ),
          const SizedBox(height: RvmSpacing.sm),
          Text(entry.message, style: text.bodyMedium),
          const SizedBox(height: RvmSpacing.sm),
          Text(
            [entry.employeeName, entry.employeeCode]
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty)
                .join(' · '),
            style: text.labelMedium?.copyWith(color: p.muted),
          ),
          if (entry.context.summary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              entry.context.summary,
              style: text.bodySmall?.copyWith(color: p.subtle),
            ),
          ],
          if (entry.hasScreenshot) ...[
            const SizedBox(height: RvmSpacing.sm),
            TextButton.icon(
              onPressed: () => _openScreenshot(context, entry.id),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('View screenshot'),
            ),
          ],
        ],
      ),
    );
  }

  static String _when(DateTime? at) {
    if (at == null) return '';
    final d = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _openScreenshot(BuildContext context, String id) async {
    final repo = getIt<EssRepository>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: FutureBuilder<AppFeedbackScreenshot>(
            future: repo.feedbackScreenshot(id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final failure = snapshot.error;
              if (snapshot.hasError || failure != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(RvmSpacing.lg),
                    child: Text(
                      failure is Failure
                          ? failure.message
                          : 'The screenshot could not be opened.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final file = snapshot.data;
              if (file == null || file.url.isEmpty) {
                return const Center(child: Text('No screenshot.'));
              }
              return InteractiveViewer(
                child: Image.network(
                  file.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text('The screenshot link has expired. Try again.'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

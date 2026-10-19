import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import 'bloc/wall_bloc.dart';
import 'create_post_sheet.dart';
import 'praise_sheet.dart';
import 'wall_widgets.dart';

/// Phase 2A: the Wall — feed, celebrations, announcements, praise, polls and reactions.
class WallScreen extends StatelessWidget {
  const WallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<WallBloc>()..add(const WallLoadRequested()),
      child: const _WallView(),
    );
  }
}

class _WallView extends StatelessWidget {
  const _WallView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WallBloc, WallState>(
      listenWhen: (a, b) => a.actionFailure != b.actionFailure,
      listener: (context, state) {
        final msg = state.actionFailure?.message;
        if (msg != null) {
          ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(msg)));
        }
      },
      builder: (context, state) => Scaffold(
        body: Column(
          children: [
            TeamPageHeader(
              title: 'Wall',
              subtitle: const Text('Company feed, praise and announcements'),
              actions: [
                Builder(
                  builder: (context) {
                    final caps = context.watch<CapabilitiesBloc>().state.data;
                    if (caps == null || (!caps.wallModerate && !caps.wallAnnounce)) {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      tooltip: 'Wall desk',
                      onPressed: () => context.push('/wall/moderation'),
                      icon: const Icon(Icons.shield_outlined),
                    );
                  },
                ),
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Settings',
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => const _WallSettingsSheet(),
                    ),
                    icon: const Icon(Icons.tune),
                  ),
                ),
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => context.read<WallBloc>().add(const WallRefreshed()),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ],
            ),
            Expanded(child: _body(context, state)),
          ],
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'praise',
              onPressed: () => showPraiseSheet(context),
              tooltip: 'Praise someone',
              child: const Icon(Icons.emoji_events_outlined),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.extended(
              heroTag: 'post',
              onPressed: () => showCreatePostSheet(context),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WallState state) {
    if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) return const AppLoading();
    if (state.status == LoadStatus.failure) {
      return AppError(
        message: state.failure?.message ?? 'Could not load the Wall.',
        onRetry: () => context.read<WallBloc>().add(const WallRefreshed()),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => context.read<WallBloc>().add(const WallRefreshed()),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, 96),
        children: [
          if (state.celebrations != null && !state.celebrations!.isEmpty) ...[
            CelebrationsCard(celebrations: state.celebrations!),
            const SizedBox(height: RvmSpacing.md),
          ],
          for (final a in state.announcements.take(3)) ...[
            AnnouncementCard(announcement: a),
            const SizedBox(height: RvmSpacing.md),
          ],
          if (state.posts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: AppEmpty(icon: Icons.forum_outlined, message: 'The Wall is quiet. Start the first post.'),
            )
          else
            for (final p in state.posts) ...[
              WallPostCard(
                post: p,
                onReact: (reaction) => context.read<WallBloc>().add(WallReacted(postId: p.id, reaction: reaction)),
                onOpen: () => context.push('/wall/post/${p.id}'),
                onEdit: p.mine ? () => _editPost(context, p) : null,
                onDelete: p.mine ? () => _deletePost(context, p) : null,
                onReport: p.mine ? null : () => _reportPost(context, p),
                onWhoReacted: (p.reactions?.total ?? 0) > 0 ? () => _whoReacted(context, p.id) : null,
                onPollChanged: () => context.read<WallBloc>().add(const WallRefreshed()),
              ),
              const SizedBox(height: RvmSpacing.md),
            ],
        ],
      ),
    );
  }
}

Future<void> _editPost(BuildContext context, WallPost post) async {
  final controller = TextEditingController(text: post.body ?? '');
  final text = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Edit post'),
      content: TextField(controller: controller, minLines: 3, maxLines: 8, maxLength: 2000),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
      ],
    ),
  );
  if (text == null || text.isEmpty || !context.mounted) return;
  try {
    await getIt<EssRepository>().editWallPost(post.id, text);
    if (context.mounted) context.read<WallBloc>().add(const WallRefreshed());
  } on Failure catch (f) {
    if (context.mounted) _snack(context, f.message);
  }
}

Future<void> _deletePost(BuildContext context, WallPost post) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete this post?'),
      content: const Text('This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await getIt<EssRepository>().deleteWallPost(post.id);
    if (context.mounted) context.read<WallBloc>().add(const WallRefreshed());
  } on Failure catch (f) {
    if (context.mounted) _snack(context, f.message);
  }
}

Future<void> _reportPost(BuildContext context, WallPost post) async {
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Report this post'),
      content: TextField(controller: controller, minLines: 2, maxLines: 4, maxLength: 280, decoration: const InputDecoration(hintText: 'Why are you reporting it?')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Report')),
      ],
    ),
  );
  if (reason == null || reason.length < 3 || !context.mounted) return;
  try {
    await getIt<EssRepository>().reportPost(post.id, reason: reason);
    if (context.mounted) _snack(context, 'Reported to HR.');
  } on Failure catch (f) {
    if (context.mounted) _snack(context, f.message);
  }
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));

void _whoReacted(BuildContext context, String postId) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ReactionBreakdownSheet(postId: postId),
    );

/// F6: whether my birthday/anniversary shows on the Wall.
class _WallSettingsSheet extends StatefulWidget {
  const _WallSettingsSheet();

  @override
  State<_WallSettingsSheet> createState() => _WallSettingsSheetState();
}

class _WallSettingsSheetState extends State<_WallSettingsSheet> {
  bool _loading = true;
  bool _saving = false;
  bool _hidden = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final hidden = await getIt<EssRepository>().celebrationOptout();
      if (!mounted) return;
      setState(() {
        _hidden = hidden;
        _loading = false;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _error = f.message;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool hidden) async {
    setState(() {
      _hidden = hidden;
      _saving = true;
    });
    try {
      await getIt<EssRepository>().setCelebrationOptout(hidden);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _hidden = !hidden);
      _snack(context, f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RvmSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(RvmSpacing.md, 0, RvmSpacing.md, RvmSpacing.sm),
            child: Text('Wall settings', style: Theme.of(context).textTheme.titleLarge),
          ),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
          else
            SwitchListTile(
              value: _hidden,
              onChanged: _saving ? null : _toggle,
              title: const Text('Hide my celebrations'),
              subtitle: const Text('Your birthday and anniversary stay off the Wall and out of the feed.'),
            ),
        ],
      ),
    );
  }
}

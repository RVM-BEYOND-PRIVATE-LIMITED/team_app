import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import 'bloc/notifications_bloc.dart';

/// D6/D8: the notifications Inbox, unread count and category opt-outs.
/// Backend: `/api/ess/notifications` (Phase 1D).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<NotificationsBloc>()..add(const NotificationsLoadRequested()),
      child: const _NotificationsView(),
    );
  }
}

class _NotificationsView extends StatelessWidget {
  const _NotificationsView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsBloc, NotificationsState>(
      builder: (context, state) {
        return Scaffold(
          body: Column(
            children: [
              TeamPageHeader(
                title: 'Notifications',
                subtitle: Text(state.unread > 0
                    ? '${state.unread} unread'
                    : 'You are all caught up'),
                actions: [
                  Builder(
                    builder: (context) => TeamHeaderAction(
                      icon: Icons.tune_rounded,
                      tooltip: 'Settings',
                      onPressed: () => _openSettings(context),
                    ),
                  ),
                  Builder(
                    builder: (context) => TeamHeaderAction(
                      icon: Icons.done_all_rounded,
                      tooltip: 'Mark all read',
                      onPressed: state.unread == 0
                          ? null
                          : () => context
                              .read<NotificationsBloc>()
                              .add(const NotificationsReadAllRequested()),
                    ),
                  ),
                ],
              ),
              Expanded(child: _body(context, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, NotificationsState state) {
    final page = state.page;
    if (state.status == LoadStatus.initial ||
        (state.status == LoadStatus.loading && page == null)) {
      return const AppLoading();
    }
    if (state.status == LoadStatus.failure && page == null) {
      return AppError(
        message: state.failure?.message ?? 'Could not load notifications.',
        onRetry: () => context
            .read<NotificationsBloc>()
            .add(const NotificationsRefreshed()),
      );
    }
    if (page == null || page.notifications.isEmpty) {
      return const AppEmpty(
          icon: Icons.notifications_none, message: 'No notifications yet.');
    }
    return RefreshIndicator(
      onRefresh: () async =>
          context.read<NotificationsBloc>().add(const NotificationsRefreshed()),
      child: ListView.separated(
        padding: const EdgeInsets.all(RvmSpacing.md),
        itemCount: page.notifications.length,
        separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
        itemBuilder: (context, i) =>
            _NotificationTile(notification: page.notifications[i]),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    final bloc = context.read<NotificationsBloc>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          BlocProvider.value(value: bloc, child: const _SettingsSheet()),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});
  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: notification.unread
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: ListTile(
        onTap: notification.unread
            ? () => context
                .read<NotificationsBloc>()
                .add(NotificationReadRequested(notification.id))
            : null,
        leading: CircleAvatar(
          backgroundColor: notification.unread
              ? scheme.primary
              : scheme.surfaceContainerHighest,
          child: Icon(_icon(notification.category),
              size: 18,
              color: notification.unread
                  ? scheme.onPrimary
                  : scheme.onSurfaceVariant),
        ),
        title: Text(notification.title,
            style: TextStyle(
                fontWeight:
                    notification.unread ? FontWeight.w700 : FontWeight.w500)),
        subtitle: Text(notification.body,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: notification.createdAt == null
            ? null
            : Text(_when(notification.createdAt!),
                style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }

  static IconData _icon(String category) => switch (category) {
        'approvals' => Icons.fact_check_outlined,
        'decisions' => Icons.task_alt,
        'priority_tasks' => Icons.flag_outlined,
        'mentions' => Icons.alternate_email,
        'replies' => Icons.reply,
        'praise' => Icons.emoji_events_outlined,
        'announcements' => Icons.campaign_outlined,
        'acknowledgements' => Icons.mark_email_read_outlined,
        'polls' => Icons.poll_outlined,
        'helpdesk' => Icons.support_agent,
        _ => Icons.notifications_none,
      };

  static String _when(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${local.day}/${local.month}';
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsBloc, NotificationsState>(
      builder: (context, state) {
        final settings = state.settings;
        return Padding(
          padding: const EdgeInsets.only(bottom: RvmSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    RvmSpacing.md, 0, RvmSpacing.md, RvmSpacing.sm),
                child: Text('Notification settings',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              if (settings == null)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()))
              else ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: RvmSpacing.md),
                  child: Text(
                    'Quiet hours ${settings.quietFrom ?? '21:00'}–${settings.quietTo ?? '08:00'} IST',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (final c in settings.categories)
                  SwitchListTile(
                    value: c.enabled,
                    onChanged: state.savingSettings
                        ? null
                        : (v) => context.read<NotificationsBloc>().add(
                            NotificationSettingToggled(
                                category: c.category, enabled: v)),
                    title: Text(c.label),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

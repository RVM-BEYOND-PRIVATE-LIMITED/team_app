import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app_crash.dart';
import '../../auth/team_permissions.dart';
import '../../bloc/team_auth_bloc.dart';
import '../work/wfh_sheet.dart';
import '../../domain/attendance_models.dart';
import '../../domain/ess_models.dart';
import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import '../../widgets/team_kit.dart';
import '../attendance/bloc/punch_bloc.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TeamAuthBloc, TeamAuthState>(
      builder: (context, auth) {
        final identity = auth.identity;
        final attendance = identity?.attendance == true;
        final perms =
            TeamPermissions.forRole(identity?.role ?? AppRole.unknown);
        return Scaffold(
          backgroundColor: RvmColors.ivory,
          body: Column(
            children: [
              const OfflineBanner(),
              Expanded(
                child: NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    TeamCollapsingHeader(
                      contentHeight: 144,
                      title: (identity?.username?.trim().isNotEmpty == true
                          ? identity!.username!.trim()
                          : 'Home'),
                      actions: [
                        TeamHeaderAction(
                          icon: Icons.notifications_none_rounded,
                          tooltip: 'Notifications',
                          badge: true,
                          onPressed: () => context.push('/notifications'),
                        ),
                      ],
                      expanded: _HomeHeader(identity: identity),
                    ),
                  ],
                  body: RefreshIndicator(
                    color: RvmColors.clay,
                    onRefresh: () async {},
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(RvmSpacing.md,
                              RvmSpacing.md, RvmSpacing.md, RvmSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _ScheduleCard(),
                              const SizedBox(height: RvmSpacing.md),
                              _OffThisWeekCard(),
                              const SizedBox(height: RvmSpacing.md),
                              if (perms.canSeeFacultyWork) ...[
                                _FacultyCard(),
                                const SizedBox(height: RvmSpacing.md),
                              ],
                              if (perms.canSeeHodWork) ...[
                                _HodCard(),
                                const SizedBox(height: RvmSpacing.md),
                              ],
                              if (!attendance && perms.canSeePriorityTasks) ...[
                                _PrioritySummaryCard(),
                                const SizedBox(height: RvmSpacing.md),
                              ],
                              // Interviews, priority tasks and announcements are
                              // Scheduler reads. An attendance-only session's punch
                              // token is accepted only on the punch routes, so these
                              // would answer 401. The ESS cards above still work.
                              if (!attendance) ...[
                                _InterviewsCard(perms: perms),
                                const SizedBox(height: RvmSpacing.md),
                                _QuickActions(perms: perms),
                                const SizedBox(height: RvmSpacing.md),
                                _WorkFromHomeCard(),
                                const SizedBox(height: RvmSpacing.md),
                                _AnnouncementsSection(),
                              ] else ...[
                                _QuickActions(perms: perms),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.identity});
  final StaffIdentity? identity;

  @override
  Widget build(BuildContext context) {
    final name = identity?.username ?? 'Welcome';
    final trimmed = name.trim();
    final role = appRoleLabel(identity?.role ?? AppRole.unknown).toUpperCase();
    final location = identity?.locationName;

    return TeamPageHeader(
      eyebrow: _greeting(DateTime.now().hour),
      title: name,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          TeamAvatar(name: trimmed, size: 48, rounded: true),
          Positioned(
            right: 0,
            bottom: 1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: RvmColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: RvmColors.ironwood, width: 2),
              ),
            ),
          ),
        ],
      ),
      actions: [
        const TeamBrandMark(),
        TeamHeaderAction(
          icon: Icons.notifications_none_rounded,
          tooltip: 'Notifications',
          badge: true,
          onPressed: () => context.push('/notifications'),
        ),
      ],
      footer: Row(
        children: [
          TeamHeaderPill(label: role),
          if (location != null && location.isNotEmpty) ...[
            const SizedBox(width: RvmSpacing.sm),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 12, color: RvmColors.ivory.withValues(alpha: 0.7)),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: RvmColors.ivory.withValues(alpha: 0.72),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _greeting(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

// ── today's schedule ──────────────────────────────────────────────────────

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard();

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<PunchBloc>()..add(const PunchLoadRequested(withDistance: true)),
      child: BlocConsumer<PunchBloc, PunchState>(
        listenWhen: (a, b) => a.message != b.message,
        listener: (context, state) {
          final message = state.message;
          if (message != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          }
        },
        builder: (context, state) {
          final data = state.data;
          final today = data?.today;
          final shift = data?.shift;
          final onDuty = today?.punchedIn ?? false;
          final done = today?.done ?? false;
          final shiftText = (shift?.start != null && shift?.end != null)
              ? '${_prettyTime(shift?.start ?? '')} – ${_prettyTime(shift?.end ?? '')}'
              : 'Shift not set';
          final logged = today?.firstIn;
          return TeamCard(
            child: Column(
              children: [
                Row(
                  children: [
                    TeamIconBadge(
                      icon: Icons.schedule_rounded,
                      color: RvmColors.success,
                      background: RvmColors.successSoft,
                      size: 38,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TODAY\'S SCHEDULE',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontSize: 9.5,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w600,
                                    color: RvmColors.muted,
                                  )),
                          const SizedBox(height: 2),
                          Text(shiftText,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                  )),
                        ],
                      ),
                    ),
                    TeamPill(
                      label: onDuty ? 'On Duty' : 'Off Duty',
                      tone:
                          onDuty ? TeamPillTone.success : TeamPillTone.neutral,
                      dot: true,
                    ),
                  ],
                ),
                const Divider(height: 25),
                Row(
                  children: [
                    Icon(Icons.schedule_outlined,
                        size: 14, color: RvmColors.subtle),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        logged == null
                            ? 'Not punched in yet'
                            : 'Logged in at ${TimeOfDay.fromDateTime(logged.toLocal()).format(context)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 11.5,
                              color: RvmColors.muted,
                            ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.push('/me/attendance'),
                      child: Text('View logs',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontSize: 11.5,
                                    color: RvmColors.clay,
                                    fontWeight: FontWeight.w600,
                                  )),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _HomePunchButton(
                  onDuty: onDuty,
                  done: done,
                  busy: state.punching,
                  onPressed: state.punching
                      ? null
                      : () {
                          final reason = _homePunchBlock(data);
                          if (reason != null) {
                            final messenger = ScaffoldMessenger.of(context);
                            messenger
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(
                                content: Text(reason),
                                action: data?.mustSetPassword == true
                                    ? SnackBarAction(
                                        label: 'Set password',
                                        onPressed: () =>
                                            context.push('/me/punch'),
                                      )
                                    : null,
                              ));
                            return;
                          }
                          context
                              .read<PunchBloc>()
                              .add(PunchRequested(onDuty ? 'out' : 'in'));
                        },
                ),
                const SizedBox(height: 8),
                _DistanceNote(
                  state: state,
                  onRefresh: () {
                    final bloc = context.read<PunchBloc>();
                    if (state.data == null) {
                      bloc.add(const PunchLoadRequested(withDistance: true));
                    } else {
                      bloc.add(const PunchDistanceRequested());
                    }
                  },
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _sendTestCrash(context),
                    icon: const Icon(Icons.bug_report_outlined, size: 16),
                    label: const Text('Send test crash'),
                    style: TextButton.styleFrom(
                      foregroundColor: RvmColors.danger,
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

Future<void> _sendTestCrash(BuildContext context) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Send a test crash?'),
      content: const Text(
          'This sends a fatal test report to Firebase Crashlytics. The app stays open.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Send'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;
  final sent = await CrashReporter.testCrash();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(sent
          ? 'Test crash sent. Check Firebase Crashlytics in a few minutes.'
          : 'Crashlytics is not enabled in this build. Check the debug console.'),
    ));
}

/// A bounded, human message for the cases where a punch cannot be sent. The
/// Home button never navigates: the person stays on Home and sees the reason.
String? _homePunchBlock(MyAttendance? data) {
  if (data == null) {
    return 'Attendance is still loading. Try again in a moment.';
  }
  if (!data.linked) {
    return data.message ??
        'Your login is not linked to an employee record yet.';
  }
  if (data.mustSetPassword) {
    return 'Set your attendance password before you punch.';
  }
  final device = data.device;
  if (device != null && device.thisPhone != 'own' && !device.canRegister) {
    return switch (device.thisPhone) {
      'other' =>
        'This phone is registered to another employee. Punch from your own phone.',
      'revoked' =>
        'HR has reset this phone. Punch from your new phone, or ask HR to reset it again.',
      _ =>
        'Your attendance is registered to a different phone. Ask HR to reset your phone.',
    };
  }
  return null;
}

String _distanceText(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// The Home card's distance line: how far this phone is from the branch
/// geofence centre and whether that is inside the allowed radius.
class _DistanceNote extends StatelessWidget {
  const _DistanceNote({required this.state, required this.onRefresh});

  final PunchState state;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    final branch = data?.branch;
    final radius = state.allowedRadiusMeters ?? branch?.radiusM;
    final configured = branch != null &&
        branch.configured &&
        branch.latitude != null &&
        branch.longitude != null &&
        radius != null;

    final Color color;
    final IconData icon;
    final String title;
    final String? subtitle;
    final bool loading = state.distanceLoading;

    if (data == null) {
      final failure = state.failure;
      color = failure == null ? RvmColors.muted : RvmColors.warning;
      icon = failure == null
          ? Icons.location_searching_rounded
          : Icons.cloud_off_rounded;
      title =
          failure?.message ?? 'Checking your location after attendance loads…';
      subtitle = failure == null ? null : 'Tap refresh to try again.';
    } else if (!configured) {
      color = RvmColors.warning;
      icon = Icons.location_off_rounded;
      title = 'Office geofence is not set up.';
      subtitle = 'Ask HR to set the branch location.';
    } else if (loading) {
      color = RvmColors.info;
      icon = Icons.my_location_rounded;
      title = 'Checking your distance from ${branch.name}…';
      subtitle = null;
    } else if (state.distanceError != null) {
      color = RvmColors.warning;
      icon = Icons.location_disabled_rounded;
      title = state.distanceError!;
      subtitle = 'Tap the refresh button to try again.';
    } else if (state.distanceMeters == null) {
      color = RvmColors.muted;
      icon = Icons.location_searching_rounded;
      title = 'Distance not measured yet.';
      subtitle = 'Tap refresh to check.';
    } else {
      final distance = state.distanceMeters!;
      final inside = distance <= radius;
      color = inside ? RvmColors.success : RvmColors.danger;
      icon = inside ? Icons.check_circle_rounded : Icons.location_off_rounded;
      title =
          '${inside ? 'Inside' : 'Outside'} the office geofence — ${_distanceText(distance)} away';
      subtitle = '${branch.name} · allowed radius ${_distanceText(radius)}'
          '${state.accuracyMeters == null ? '' : ' · GPS ±${state.accuracyMeters!.round()} m'}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(RvmRadii.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          loading
              ? SizedBox(
                  width: 15,
                  height: 15,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: color))
              : Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: color,
                        )),
                if (subtitle != null)
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 9,
                            color: RvmColors.muted,
                          )),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh distance',
            onPressed: onRefresh,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            color: RvmColors.subtle,
          ),
        ],
      ),
    );
  }
}

/// The Home tab's one-tap punch. Green while the person is on duty, red once
/// they have punched out for the day, so the state is readable at a glance.
class _HomePunchButton extends StatelessWidget {
  const _HomePunchButton({
    required this.onDuty,
    required this.done,
    required this.busy,
    required this.onPressed,
  });

  final bool onDuty;
  final bool done;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? RvmColors.danger
        : onDuty
            ? RvmColors.success
            : RvmColors.clay;
    final label = done
        ? 'Punched Out'
        : onDuty
            ? 'Punch Out'
            : 'Punch In';
    final icon = done
        ? Icons.check_circle_rounded
        : onDuty
            ? Icons.logout_rounded
            : Icons.login_rounded;
    return SizedBox(
      height: 46,
      child: FilledButton(
        onPressed: done || busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: done ? color : color.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 17),
                  const SizedBox(width: 8),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }
}

String _prettyTime(String value) {
  // The API returns 24h "HH:MM"; the design shows a friendly 12h range.
  final parts = value.split(':');
  if (parts.length < 2) return value;
  final hour = int.tryParse(parts[0]);
  final minute = parts[1];
  if (hour == null) return value;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:$minute $suffix';
}

// ── off this week ─────────────────────────────────────────────────────────

class _OffThisWeekCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<LoadBloc<TeamOffWeek>>()..add(const LoadRequested()),
      child: BlocBuilder<LoadBloc<TeamOffWeek>, LoadState<TeamOffWeek>>(
        builder: (context, state) {
          final data = state.data;
          final count = data?.people.length;
          final body = switch (state.status) {
            LoadStatus.loading || LoadStatus.initial => const SizedBox(
                height: 34,
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2))),
            LoadStatus.failure => const SizedBox.shrink(),
            _ => _OffThisWeekInner(people: data?.people ?? const []),
          };
          return TeamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TeamSectionHeader(
                  title: 'Off this week',
                  trailing: Text(
                    count == null ? 'Team' : 'Team ($count)',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 11),
                  ),
                ),
                const SizedBox(height: 10),
                body,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OffThisWeekInner extends StatelessWidget {
  const _OffThisWeekInner({required this.people});
  final List<OffWeekPerson> people;

  @override
  Widget build(BuildContext context) {
    final text = people.isEmpty
        ? 'Nobody is off this week. Full team present!'
        : people
            .map((p) => '${p.card.fullName} · ${p.days.join(', ')}')
            .join('\n');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: RvmColors.cream,
        borderRadius: BorderRadius.circular(RvmRadii.md),
        border: Border.all(color: RvmColors.sand),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      height: 1.35,
                      color: RvmColors.muted,
                    )),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => context.push('/team/directory'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: RvmColors.clay,
            ),
            child: const Text('Calendar',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── role work cards ───────────────────────────────────────────────────────

class _FacultyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TeamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TeamSectionHeader(
            title: "Today's classes",
            trailing: TextButton(
              onPressed: () => context.push('/work/batches'),
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28), padding: EdgeInsets.zero),
              child: const Text('My batches', style: TextStyle(fontSize: 11.5)),
            ),
          ),
          const SizedBox(height: 6),
          Text('Open your batches to mark today’s student attendance.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.push('/work/indicators'),
            icon: const Icon(Icons.insights_outlined, size: 17),
            label: const Text('My attendance health'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40)),
          ),
        ],
      ),
    );
  }
}

class _HodCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TeamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TeamSectionHeader(
            title: 'Faculty Development',
            trailing: TextButton(
              onPressed: () => context.push('/work/hod'),
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28), padding: EdgeInsets.zero),
              child: const Text('Open', style: TextStyle(fontSize: 11.5)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
              'Your team to-do list, interview verdicts, risk logs and day comments.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PrioritySummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<InboxBloc>()..add(const LoadRequested()),
      child: BlocBuilder<InboxBloc, LoadState<PriorityInbox>>(
        builder: (context, state) {
          return TeamCard(
            onTap: () => context.push('/notifications'),
            child: Row(
              children: [
                TeamIconBadge(
                  icon: Icons.flag_outlined,
                  color: RvmColors.teamSeed,
                  background: const Color(0xFFFCEBE2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Priority tasks',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        switch (state.status) {
                          LoadStatus.loading ||
                          LoadStatus.initial =>
                            'Loading…',
                          LoadStatus.failure =>
                            state.failure?.message ?? 'Could not load tasks.',
                          LoadStatus.empty =>
                            'Nothing on your plate right now.',
                          LoadStatus.success =>
                            '${state.data!.outstanding} outstanding · ${state.data!.unread} unread',
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: RvmColors.subtle),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InterviewsCard extends StatelessWidget {
  const _InterviewsCard({required this.perms});
  final TeamPermissions perms;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<InterviewsBloc>()..add(const LoadRequested()),
      child: BlocBuilder<InterviewsBloc, LoadState<List<InterviewRound>>>(
        builder: (context, state) {
          if (state.status == LoadStatus.failure ||
              state.status == LoadStatus.empty) {
            return const SizedBox.shrink();
          }
          final round = (state.data ?? const <InterviewRound>[]).isNotEmpty
              ? state.data!.first
              : null;
          if (round == null) return const SizedBox.shrink();
          return TeamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TeamSectionHeader(
                  title: 'Next interview (24h)',
                  trailing: TextButton(
                    onPressed: () => context.push('/work/interviews'),
                    style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: EdgeInsets.zero),
                    child: const Text('All', style: TextStyle(fontSize: 11.5)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(round.candidateName ?? 'Candidate',
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (round.position != null)
                  Text(round.position!,
                      style: Theme.of(context).textTheme.bodySmall),
                if (round.scheduledAt != null)
                  Text(
                      'At ${TimeOfDay.fromDateTime(round.scheduledAt!.toLocal()).format(context)}',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── quick actions ─────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.perms});
  final TeamPermissions perms;

  @override
  Widget build(BuildContext context) {
    final caps = context.watch<CapabilitiesBloc>().state.data;
    final actions = <_QuickAction>[
      // The punch itself lives in the schedule card above, so this row does not
      // send anyone to the full punch screen.
      _QuickAction(Icons.today_outlined, 'My day', 'Tasks & meetings',
          RvmColors.info, RvmColors.infoSoft, '/me/attendance'),
      _QuickAction(
          Icons.event_note_outlined,
          'Requests & leave',
          'Apply vacation',
          RvmColors.teamSeed,
          const Color(0xFFFCEBE2),
          '/requests'),
      if (caps?.approvalsOwnReports == true ||
          caps?.approvalsAnyRequest == true)
        _QuickAction(Icons.fact_check_outlined, 'Approvals', 'Pending reviews',
            RvmColors.warning, RvmColors.warningSoft, '/approvals',
            badge: '2 new'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TeamSectionHeader(
          title: 'Quick actions',
          caption: 'Personal & Team',
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final a in actions)
                  SizedBox(width: width, child: _QuickTile(action: a)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuickAction {
  const _QuickAction(this.icon, this.title, this.subtitle, this.color,
      this.background, this.route,
      {this.badge});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color background;
  final String route;
  final String? badge;
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.action});
  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    return TeamCard(
      padding: const EdgeInsets.all(12),
      radius: RvmRadii.md,
      onTap: () => context.push(action.route),
      child: SizedBox(
        height: 88,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TeamIconBadge(
                  icon: action.icon,
                  color: action.color,
                  background: action.background,
                  size: 34,
                  iconSize: 17,
                  radius: 10,
                ),
                const Spacer(),
                Text(action.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(action.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 10.5)),
              ],
            ),
            if (action.badge != null)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: RvmColors.teamSeed,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(action.badge!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                          )),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkFromHomeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TeamCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => showWfhSheet(context),
      child: Row(
        children: [
          const TeamIconBadge(
            icon: Icons.desktop_windows_outlined,
            color: RvmColors.success,
            background: RvmColors.successSoft,
            size: 36,
            iconSize: 18,
            radius: 11,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Work from home',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontSize: 13)),
                const SizedBox(height: 1),
                Text('Request a work-from-home day',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 10.5)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 20, color: RvmColors.subtle),
        ],
      ),
    );
  }
}

// ── announcements ─────────────────────────────────────────────────────────

class _AnnouncementsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<HomeAnnouncementsBloc>()..add(const LoadRequested()),
      child:
          BlocBuilder<HomeAnnouncementsBloc, LoadState<List<TeamAnnouncement>>>(
        builder: (context, state) {
          return TeamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TeamSectionHeader(
                  title: 'Announcements',
                  trailing: TextButton(
                    onPressed: () => context.push('/notifications'),
                    style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: EdgeInsets.zero),
                    child:
                        const Text('History', style: TextStyle(fontSize: 11.5)),
                  ),
                ),
                const SizedBox(height: 10),
                switch (state.status) {
                  LoadStatus.loading || LoadStatus.initial => const SizedBox(
                      height: 40,
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2))),
                  LoadStatus.failure => Text(
                      state.failure?.message ?? 'Could not load announcements.',
                      style: Theme.of(context).textTheme.bodySmall),
                  LoadStatus.empty => const _AnnouncementEmpty(),
                  LoadStatus.success => Column(
                      children: [
                        for (final a in state.data!.take(4))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: RvmColors.cream,
                                borderRadius:
                                    BorderRadius.circular(RvmRadii.sm),
                                border: Border.all(color: RvmColors.sand),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.campaign_outlined,
                                      size: 16, color: RvmColors.muted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(a.title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    color: RvmColors.ink)),
                                        Text(a.message,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(fontSize: 10.5)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                },
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AnnouncementEmpty extends StatelessWidget {
  const _AnnouncementEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: RvmColors.cream,
        borderRadius: BorderRadius.circular(RvmRadii.md),
      ),
      child: Column(
        children: [
          Text('No new company announcements right now.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontSize: 11)),
          const SizedBox(height: 2),
          Text('Stay tuned for future company updates.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontSize: 9.5, color: RvmColors.subtle)),
        ],
      ),
    );
  }
}

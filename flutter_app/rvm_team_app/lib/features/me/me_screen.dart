import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/team_permissions.dart';
import '../../bloc/team_auth_bloc.dart';
import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import '../../widgets/team_kit.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeamAuthBloc>().state;
    if (auth.identity?.attendance == true) {
      return _AttendanceMe(auth: auth);
    }
    return BlocProvider(
      create: (_) => getIt<MeBloc>()..add(const LoadRequested()),
      child: Scaffold(
        backgroundColor: RvmColors.ivory,
        body: Column(
          children: [
            TeamPageHeader(
              title: 'Me',
              eyebrow: 'My account',
              subtitle: const Text('Your profile, work and account'),
              actions: [
                Builder(
                  builder: (context) => TeamHeaderAction(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh',
                    onPressed: () =>
                        context.read<MeBloc>().add(const LoadRefreshed()),
                  ),
                ),
              ],
            ),
            Expanded(
              child: BlocBuilder<MeBloc, LoadState<TeamProfile>>(
                builder: (context, state) {
                  return switch (state.status) {
                    LoadStatus.loading ||
                    LoadStatus.initial =>
                      const AppLoading(),
                    LoadStatus.failure => AppError(
                        message: state.failure?.message ??
                            'Could not load your profile.',
                        onRetry: () =>
                            context.read<MeBloc>().add(const LoadRefreshed()),
                      ),
                    _ => _MeBody(profile: state.data),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Me for an attendance-only sign-in. The Scheduler `/me` profile is not
/// available to a punch token, so the header uses the name from the attendance
/// login and only the ESS-backed tiles are shown. This keeps the Me tab useful
/// without a 401 from the Scheduler.
class _AttendanceMe extends StatelessWidget {
  const _AttendanceMe({required this.auth});
  final TeamAuthState auth;

  @override
  Widget build(BuildContext context) {
    final profile = TeamProfile(
      id: auth.identity?.userId ?? '',
      username: auth.attendanceName?.trim().isNotEmpty == true
          ? auth.attendanceName!.trim()
          : 'My account',
      role: 'attendance',
    );
    return Scaffold(
      backgroundColor: RvmColors.ivory,
      body: Column(
        children: [
          const TeamPageHeader(
            title: 'Me',
            eyebrow: 'My account',
            subtitle: Text('Your profile, documents and requests'),
          ),
          Expanded(child: _MeBody(profile: profile, attendanceOnly: true)),
        ],
      ),
    );
  }
}

class _MeBody extends StatelessWidget {
  const _MeBody({this.profile, this.attendanceOnly = false});
  final TeamProfile? profile;
  final bool attendanceOnly;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeamAuthBloc>().state;
    final perms =
        TeamPermissions.forRole(auth.identity?.role ?? AppRole.unknown);
    final caps = context.watch<CapabilitiesBloc>().state.data;
    final p = profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ProfileHeader(profile: p),
        const SizedBox(height: RvmSpacing.lg),
        _Section(
          title: 'Me',
          children: [
            _Tile(
                icon: Icons.fingerprint,
                title: 'Punch in / out',
                subtitle: 'Geofenced punch, remarks',
                onTap: () => context.push('/me/punch')),
            _Tile(
                icon: Icons.today_outlined,
                title: 'My day',
                subtitle: 'Today from the server’s clock, HR’s remark',
                onTap: () => context.push('/me/attendance')),
            _Tile(
                icon: Icons.person_outline,
                title: 'Work profile',
                subtitle: 'Summary, job and timeline',
                onTap: () => context.push('/me/profile')),
            _Tile(
                icon: Icons.badge_outlined,
                title: 'Personal details',
                subtitle: 'Blood group, emergency contact',
                onTap: () => context.push('/me/personal')),
            _Tile(
                icon: Icons.folder_open_outlined,
                title: 'Documents',
                subtitle: 'Upload and track verification',
                onTap: () => context.push('/me/documents')),
            _Tile(
                icon: Icons.account_balance_outlined,
                title: 'Bank details',
                subtitle: 'Saved with your consent',
                onTap: () => context.push('/me/bank')),
            _Tile(
                icon: Icons.badge,
                title: 'ID card',
                subtitle: 'Your employee card and verify link',
                onTap: () => context.push('/me/id-card')),
            _Tile(
                icon: Icons.edit_note,
                title: 'Profile changes',
                subtitle: 'Ask HR to correct your record',
                onTap: () => context.push('/me/change-requests')),
            _Tile(
                icon: Icons.privacy_tip_outlined,
                title: 'Data requests',
                subtitle: 'Correct or delete your data',
                onTap: () => context.push('/me/data-requests')),
          ],
        ),
        if (!attendanceOnly) ...[
          const SizedBox(height: RvmSpacing.md),
          _Section(
            title: 'Work',
            children: [
              if (perms.canSeeFacultyWork) ...[
                _Tile(
                    icon: Icons.menu_book_outlined,
                    title: 'My batches',
                    subtitle: 'Mark student attendance',
                    onTap: () => context.push('/work/batches')),
                _Tile(
                    icon: Icons.today_outlined,
                    title: 'My day (faculty)',
                    subtitle: 'Today\'s sessions and indicators',
                    onTap: () => context.push('/work/my-day')),
                _Tile(
                    icon: Icons.insights_outlined,
                    title: 'My indicators',
                    subtitle: 'Attendance health across my sessions',
                    onTap: () => context.push('/work/indicators')),
              ],
              if (auth.identity?.role == AppRole.ceo ||
                  auth.identity?.role == AppRole.superAdmin)
                _Tile(
                    icon: Icons.insights,
                    title: 'Leaders overview',
                    subtitle: 'Headcount, attendance and the approval queue',
                    onTap: () => context.push('/leaders')),
              if (perms.canSeeHodWork)
                _Tile(
                    icon: Icons.school_outlined,
                    title: 'Faculty Development',
                    subtitle: 'To-do, risk logs, verdicts, comments',
                    onTap: () => context.push('/work/hod')),
              _Tile(
                  icon: Icons.event_note_outlined,
                  title: 'Interviews',
                  subtitle: 'Your next rounds as a panel member',
                  onTap: () => context.push('/work/interviews')),
              if (caps?.canSeeHrTools ?? false)
                _Tile(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'HR tools',
                    subtitle: 'Requests, location reports, phones',
                    onTap: () => context.push('/hr/tools')),
            ],
          ),
        ],
        const SizedBox(height: RvmSpacing.md),
        _Section(
          title: 'Account',
          children: [
            if (!attendanceOnly) ...[
              _Tile(
                  icon: Icons.shield_outlined,
                  title: 'Account & security',
                  subtitle: 'Password, email, phone, two-factor',
                  onTap: () => context.push('/account/security')),
            ],
            _Tile(
                icon: Icons.devices_other_outlined,
                title: 'Signed-in devices',
                subtitle: 'Sign out other phones',
                onTap: () => context.push('/me/sessions')),
            if (!attendanceOnly)
              _Tile(
                  icon: Icons.history,
                  title: 'Security activity',
                  subtitle: 'Recent sign-ins and changes',
                  onTap: () => context.push('/account/security-events')),
          ],
        ),
        const SizedBox(height: RvmSpacing.md),
        _Section(
          title: 'Support',
          children: [
            _Tile(
                icon: Icons.support_agent,
                title: 'Helpdesk',
                subtitle: 'Raise a ticket and follow its thread',
                onTap: () => context.push('/helpdesk')),
          ],
        ),
        const SizedBox(height: RvmSpacing.lg),
        OutlinedButton.icon(
          onPressed: () =>
              context.read<TeamAuthBloc>().add(const TeamSignedOut()),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: RvmSpacing.lg),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({this.profile});
  final TeamProfile? profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = profile?.username ?? '—';
    final url = profile?.photoUrl;
    return TeamCard(
      child: Row(
        children: [
          TeamAvatar(name: name, photoUrl: url, size: 56),
          const SizedBox(width: RvmSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 3),
                TeamPill(
                    label: (profile?.role ?? 'Member').toUpperCase(),
                    tone: TeamPillTone.clay,
                    dense: true),
                if (profile?.email != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(profile!.email!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                if (profile?.phoneNumber != null)
                  Text(profile!.phoneNumber!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 7),
          child: Text(title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 0.9,
                    color: RvmColors.subtle,
                    fontWeight: FontWeight.w600,
                  )),
        ),
        TeamCard(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: TeamIconBadge(icon: icon, size: 34, iconSize: 16, radius: 10),
      title: Text(title,
          style:
              Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 12.5)),
      subtitle: Text(subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
      trailing: const Icon(Icons.chevron_right_rounded,
          size: 19, color: RvmColors.subtle),
      onTap: onTap,
    );
  }
}

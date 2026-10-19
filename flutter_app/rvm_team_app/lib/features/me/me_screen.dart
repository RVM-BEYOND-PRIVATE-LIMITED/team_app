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

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<MeBloc>()..add(const LoadRequested()),
      child: Scaffold(
        body: Column(
          children: [
            TeamPageHeader(
              title: 'Me',
              subtitle: const Text('Your profile, work and account'),
              actions: [
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => context.read<MeBloc>().add(const LoadRefreshed()),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ],
            ),
            Expanded(
              child: BlocBuilder<MeBloc, LoadState<TeamProfile>>(
                builder: (context, state) {
                  return switch (state.status) {
                    LoadStatus.loading || LoadStatus.initial => const AppLoading(),
                    LoadStatus.failure => AppError(
                        message: state.failure?.message ?? 'Could not load your profile.',
                        onRetry: () => context.read<MeBloc>().add(const LoadRefreshed()),
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

class _MeBody extends StatelessWidget {
  const _MeBody({this.profile});
  final TeamProfile? profile;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeamAuthBloc>().state;
    final perms = TeamPermissions.forRole(auth.identity?.role ?? AppRole.unknown);
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
            _Tile(icon: Icons.fingerprint, title: 'Punch in / out', subtitle: 'Geofenced punch, remarks', onTap: () => context.push('/me/punch')),
            _Tile(icon: Icons.today_outlined, title: 'My day', subtitle: 'Today from the server’s clock, HR’s remark', onTap: () => context.push('/me/attendance')),
            _Tile(icon: Icons.badge_outlined, title: 'Personal details', subtitle: 'Blood group, emergency contact', onTap: () => context.push('/me/personal')),
            _Tile(icon: Icons.privacy_tip_outlined, title: 'Data requests', subtitle: 'Correct or delete your data', onTap: () => context.push('/me/data-requests')),
          ],
        ),
        const SizedBox(height: RvmSpacing.md),
        _Section(
          title: 'Work',
          children: [
            if (perms.canSeeFacultyWork) ...[
              _Tile(icon: Icons.menu_book_outlined, title: 'My batches', subtitle: 'Mark student attendance', onTap: () => context.push('/work/batches')),
              _Tile(icon: Icons.insights_outlined, title: 'My indicators', subtitle: 'Attendance health across my sessions', onTap: () => context.push('/work/indicators')),
            ],
            if (perms.canSeeHodWork)
              _Tile(icon: Icons.school_outlined, title: 'Faculty Development', subtitle: 'To-do, risk logs, verdicts, comments', onTap: () => context.push('/work/hod')),
            _Tile(icon: Icons.event_note_outlined, title: 'Interviews', subtitle: 'Your next rounds as a panel member', onTap: () => context.push('/work/interviews')),
            if (caps?.canSeeHrTools ?? false)
              _Tile(icon: Icons.admin_panel_settings_outlined, title: 'HR tools', subtitle: 'Requests, location reports, phones', onTap: () => context.push('/hr/tools')),
          ],
        ),
        const SizedBox(height: RvmSpacing.md),
        _Section(
          title: 'Account',
          children: [
            _Tile(icon: Icons.shield_outlined, title: 'Account & security', subtitle: 'Password, email, phone, two-factor', onTap: () => context.push('/account/security')),
            _Tile(icon: Icons.devices_other_outlined, title: 'Signed-in devices', subtitle: 'Sign out other phones', onTap: () => context.push('/me/sessions')),
            _Tile(icon: Icons.history, title: 'Security activity', subtitle: 'Recent sign-ins and changes', onTap: () => context.push('/account/security-events')),
          ],
        ),
        const SizedBox(height: RvmSpacing.md),
        _Section(
          title: 'Coming with the new backend',
          children: const [
            _PendingTile(icon: Icons.folder_shared_outlined, title: 'Documents', detail: 'Proofs, letters, ID card'),
            _PendingTile(icon: Icons.support_agent_outlined, title: 'Helpdesk', detail: 'Complaints and tickets'),
          ],
        ),
        const SizedBox(height: RvmSpacing.lg),
        OutlinedButton.icon(
          onPressed: () => context.read<TeamAuthBloc>().add(const TeamSignedOut()),
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
    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: RvmColors.teamSeed.withValues(alpha: 0.16),
          backgroundImage: (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
          child: (url == null || url.isEmpty)
              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: Theme.of(context).textTheme.headlineSmall)
              : null,
        ),
        const SizedBox(width: RvmSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text((profile?.role ?? '').toUpperCase(),
                  style: Theme.of(context).textTheme.bodySmall),
              if (profile?.email != null)
                Text(profile!.email!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              if (profile?.phoneNumber != null)
                Text(profile!.phoneNumber!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
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
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        Card(
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      enabled: false,
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text('$detail · not available yet'),
    );
  }
}

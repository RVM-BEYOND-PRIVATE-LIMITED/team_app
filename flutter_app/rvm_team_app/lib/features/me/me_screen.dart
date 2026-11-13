import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app_version.dart';
import '../../auth/team_permissions.dart';
import '../../bloc/team_auth_bloc.dart';
import '../../domain/ess_models.dart';
import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import '../../widgets/team_kit.dart';
import '../shell/tile_registry.dart';

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
      child: BlocBuilder<MeBloc, LoadState<TeamProfile>>(
        builder: (context, state) {
          final name = state.data?.username.trim();
          final title = (name != null && name.isNotEmpty)
              ? name
              : (auth.identity?.username?.trim().isNotEmpty == true
                  ? auth.identity!.username!.trim()
                  : 'Me');
          return Scaffold(
            backgroundColor: RvmColors.ivory,
            body: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                TeamCollapsingHeader(
                  contentHeight: 124,
                  title: title,
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
                  expanded: TeamPageHeader(
                    title: title,
                    eyebrow: 'My account',
                    subtitle: const Text('Your Profile'),
                    actions: [
                      const TeamBrandMark(),
                      Builder(
                        builder: (context) => TeamHeaderAction(
                          icon: Icons.refresh_rounded,
                          tooltip: 'Refresh',
                          onPressed: () => context
                              .read<MeBloc>()
                              .add(const LoadRefreshed()),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              body: switch (state.status) {
                LoadStatus.loading ||
                LoadStatus.initial =>
                  const AppLoading(),
                LoadStatus.failure => AppError(
                    message:
                        state.failure?.message ?? 'Could not load your profile.',
                    onRetry: () =>
                        context.read<MeBloc>().add(const LoadRefreshed()),
                  ),
                _ => _MeBody(profile: state.data),
              },
            ),
          );
        },
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
    // The Scheduler /me is refused to a punch token, so the header comes from
    // the ESS's own GET /me (full name, code, designation, branch) — issue #13.
    return BlocProvider(
      create: (_) => getIt<LoadBloc<EssMe>>()..add(const LoadRequested()),
      child: BlocBuilder<LoadBloc<EssMe>, LoadState<EssMe>>(
        builder: (context, state) {
          final employee = state.data?.employee;
          final fallback = employee?.fullName ??
              (auth.attendanceName?.trim().isNotEmpty == true
                  ? auth.attendanceName!.trim()
                  : null);
          final profile = TeamProfile(
            id: employee?.id ?? auth.identity?.userId ?? '',
            username: fallback ?? 'My account',
            role: 'attendance',
          );
          final title = (fallback != null && fallback.trim().isNotEmpty)
              ? fallback.trim()
              : 'Me';
          return Scaffold(
            backgroundColor: RvmColors.ivory,
            body: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                TeamCollapsingHeader(
                  contentHeight: 124,
                  title: title,
                  expanded: TeamPageHeader(
                    title: title,
                    eyebrow: 'My account',
                    subtitle: const Text('Your Profile'),
                    actions: [const TeamBrandMark()],
                  ),
                ),
              ],
              body: _MeBody(
                profile: profile,
                attendanceOnly: true,
                attendanceEmployee: employee,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MeBody extends StatelessWidget {
  const _MeBody(
      {this.profile, this.attendanceOnly = false, this.attendanceEmployee});
  final TeamProfile? profile;
  final bool attendanceOnly;

  /// The HR record behind an attendance-only sign-in, for the header.
  final EssEmployee? attendanceEmployee;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeamAuthBloc>().state;
    final caps = context.watch<CapabilitiesBloc>().state.data;
    // The sections and tiles come from the Me registry (meSectionRegistry),
    // which holds who sees each tile.
    final sections = meSectionsFor(TeamViewer(
      role: auth.identity?.role ?? AppRole.unknown,
      attendance: attendanceOnly,
      caps: caps,
    ));
    final p = profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ProfileHeader(profile: p, employee: attendanceEmployee),
        const SizedBox(height: RvmSpacing.lg),
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: RvmSpacing.md),
          _Section(
            title: sections[i].title,
            children: [
              for (final tile in sections[i].tiles)
                _Tile(
                    icon: tile.icon,
                    title: tile.title,
                    subtitle: tile.subtitle,
                    onTap: () => context.push(tile.route)),
            ],
          ),
        ],
        const SizedBox(height: RvmSpacing.lg),
        OutlinedButton.icon(
          onPressed: () =>
              context.read<TeamAuthBloc>().add(const TeamSignedOut()),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: RvmSpacing.sm),
        // Which build is actually on the phone. Cable installs used to pick up
        // a stale APK and there was no way to tell the difference; this line
        // makes it obvious (issues 22/23).
        Center(
          child: Text(
            'Team RVM v$appVersion',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontSize: 10.5, color: RvmColors.subtle),
          ),
        ),
        const SizedBox(height: RvmSpacing.lg),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({this.profile, this.employee});
  final TeamProfile? profile;

  /// Set for an attendance-only sign-in: its HR record carries the code,
  /// designation, department and branch the header shows.
  final EssEmployee? employee;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = employee?.fullName ?? profile?.username ?? '—';
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
                    label: (employee != null
                            ? 'ATTENDANCE'
                            : appRoleLabelFromWire(profile?.role))
                        .toUpperCase(),
                    tone: TeamPillTone.clay,
                    dense: true),
                if (employee != null) ...[
                  if (employee!.designation != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(employee!.designation!,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (employee!.employeeCode != null)
                          employee!.employeeCode!,
                        if (employee!.department != null)
                          employee!.department!.name,
                        if (employee!.branch != null) employee!.branch!.name,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
                if (employee == null && profile?.email != null)
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
                if (employee == null && profile?.phoneNumber != null)
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
                    fontSize: 11,
                    letterSpacing: 1,
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
      leading: TeamIconBadge(icon: icon, size: 38, iconSize: 18, radius: 11),
      title: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontSize: 12, height: 1.3)),
      trailing: const Icon(Icons.chevron_right_rounded,
          size: 20, color: RvmColors.subtle),
      onTap: onTap,
    );
  }
}

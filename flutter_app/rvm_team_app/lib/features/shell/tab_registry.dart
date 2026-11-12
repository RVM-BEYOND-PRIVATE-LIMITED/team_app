import 'package:flutter/material.dart';

import '../../auth/team_permissions.dart';
import '../home/home_screen.dart';
import '../inbox/inbox_screen.dart';
import '../me/me_screen.dart';
import '../my_team/my_team_screen.dart';
import '../wall/wall_screen.dart';

/// One bottom-navigation tab, as one viewer sees it.
class TeamTab {
  const TeamTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.body,
  });

  /// The ESS tab id (`GET /me/capabilities` → `tabs`).
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget body;
}

/// A tab the shell can show: when it is shown, and how it looks to a viewer.
class TeamTabSpec {
  const TeamTabSpec({required this.id, required this.visible, required this.tab});

  final String id;
  final bool Function(TeamViewer viewer) visible;
  final TeamTab Function(TeamViewer viewer) tab;
}

bool _everyone(TeamViewer _) => true;

const _homeTab = TeamTab(
    id: 'home',
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    body: HomeScreen());

/// The shell's tabs in order (team_app #50, item 6). A tab is shown when the
/// ESS capabilities list its id (an empty list means all of them) and its own
/// rule lets the viewer in.
final List<TeamTabSpec> teamTabRegistry = [
  TeamTabSpec(id: 'home', visible: _everyone, tab: (_) => _homeTab),
  // Priority tasks are a Scheduler read; an attendance-only punch token is
  // refused there. The Inbox tab is for portal sign-ins. Teaching roles use it
  // to mark their batches instead (KP, 27 Oct). The sales workspace refuses
  // both reads (#50).
  TeamTabSpec(
    id: 'inbox',
    visible: (v) => !v.attendance && v.perms.canSeeInbox,
    tab: (v) {
      final teaching = v.perms.canSeeFacultyWork;
      return TeamTab(
          id: 'inbox',
          label: teaching ? 'Attendance' : 'Inbox',
          icon: teaching ? Icons.fact_check_outlined : Icons.inbox_outlined,
          selectedIcon:
              teaching ? Icons.fact_check_rounded : Icons.inbox_rounded,
          body: const InboxScreen());
    },
  ),
  TeamTabSpec(
    id: 'wall',
    visible: _everyone,
    tab: (_) => const TeamTab(
        id: 'wall',
        label: 'Wall',
        icon: Icons.forum_outlined,
        selectedIcon: Icons.forum_rounded,
        body: WallScreen()),
  ),
  TeamTabSpec(
    id: 'team',
    visible: _everyone,
    tab: (_) => const TeamTab(
        id: 'team',
        label: 'My Team',
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups_rounded,
        body: MyTeamScreen()),
  ),
  TeamTabSpec(
    id: 'me',
    visible: _everyone,
    tab: (_) => const TeamTab(
        id: 'me',
        label: 'Me',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        body: MeScreen()),
  ),
];

/// The tabs [viewer] sees, in order; never empty (Home alone when nothing else
/// is allowed).
List<TeamTab> teamTabsFor(TeamViewer viewer) {
  final listed = viewer.caps?.tabs ?? const <String>[];
  final tabs = [
    for (final spec in teamTabRegistry)
      if ((listed.isEmpty || listed.contains(spec.id)) && spec.visible(viewer))
        spec.tab(viewer),
  ];
  return tabs.isEmpty ? const [_homeTab] : tabs;
}

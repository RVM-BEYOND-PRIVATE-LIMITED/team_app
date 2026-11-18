import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../../auth/team_permissions.dart';
import '../../router/module_routes.dart';
import '../crm/crm_home_screen.dart';
import '../social/social_screens.dart';
import '../tasks/tasks_screen.dart';
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
    this.sensitive = false,
  });

  /// The ESS tab id (`GET /me/capabilities` → `tabs`).
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget body;

  /// The tab shows student or lead data, so the shell blocks screenshots while
  /// it is the selected tab (team_app #52, item 1). None of today's tabs is:
  /// screenshots of Home, Inbox, the Wall, My Team and Me work as before.
  final bool sensitive;
}

/// A tab the shell can show: when it is shown, and how it looks to a viewer.
class TeamTabSpec {
  const TeamTabSpec({
    required this.id,
    required this.visible,
    required this.tab,
    this.moduleTab = false,
  });

  final String id;
  final bool Function(TeamViewer viewer) visible;
  final TeamTab Function(TeamViewer viewer) tab;

  /// A module's own tab. It does not come from the ESS capabilities list (the
  /// ESS does not know the staff modules), so only its module switch decides.
  final bool moduleTab;
}

bool _everyone(TeamViewer _) => true;

TeamTab _homeTab() => TeamTab(
    id: 'home',
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    body: HomeScreen());

/// The shell's tabs in order (team_app #50, item 6). A tab is shown when the
/// ESS capabilities list its id (an empty list means all of them) and its own
/// rule lets the viewer in.
final List<TeamTabSpec> teamTabRegistry = [
  TeamTabSpec(id: 'home', visible: _everyone, tab: (_) => _homeTab()),
  // The Sales CRM takes the slot the hidden Inbox tab leaves free for a sales
  // sign-in (team_app #50 item 6, #51). Its router guard still decides: a
  // module route that is not open falls back to /home.
  TeamTabSpec(
    id: 'crm',
    moduleTab: true,
    visible: (v) =>
        v.modules.contains(TeamModule.crm) &&
        v.role == AppRole.salesExecutive,
    tab: (_) => const TeamTab(
      id: 'crm',
      label: 'CRM',
      icon: Icons.support_agent_outlined,
      selectedIcon: Icons.support_agent,
      body: CrmHomeScreen(),
      sensitive: true,
    ),
  ),
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
    id: 'tasks',
    moduleTab: true,
    visible: (v) => v.modules.contains(TeamModule.tasks),
    tab: (_) => const TeamTab(
      id: 'tasks',
      label: 'Tasks',
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
      body: MyTasksScreen(),
    ),
  ),
  TeamTabSpec(
    id: 'social',
    moduleTab: true,
    visible: (v) => v.modules.contains(TeamModule.social),
    tab: (_) => const TeamTab(
      id: 'social',
      label: 'Social',
      icon: Icons.photo_camera_back_outlined,
      selectedIcon: Icons.photo_camera_back,
      body: SocialHomeScreen(),
    ),
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
    tab: (_) => TeamTab(
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
      if ((spec.moduleTab || listed.isEmpty || listed.contains(spec.id)) &&
          spec.visible(viewer))
        spec.tab(viewer),
  ];
  return tabs.isEmpty ? [_homeTab()] : tabs;
}

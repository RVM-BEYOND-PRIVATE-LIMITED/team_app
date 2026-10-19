import 'package:core_bloc/core_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../injection.dart';
import '../home/home_screen.dart';
import '../inbox/inbox_screen.dart';
import '../me/me_screen.dart';
import '../my_team/my_team_screen.dart';
import '../wall/wall_screen.dart';

/// The five Keka-style tabs: Home · Inbox · Wall · Me · My Team. Each is kept
/// alive in an [IndexedStack]; role work sits inside Home, Inbox and Me.
///
/// The backend's capabilities document decides which tabs this login gets
/// (`tabs`: home, inbox, wall, me, team), so a role that must not see a tab
/// never gets a destination for it.
class TeamShell extends StatefulWidget {
  const TeamShell({super.key});

  @override
  State<TeamShell> createState() => _TeamShellState();
}

class _TeamShellState extends State<TeamShell> {
  int _index = 0;

  static const _allTabs = ['home', 'inbox', 'wall', 'me', 'team'];

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<CapabilitiesBloc>()..add(const LoadRequested()),
      child: _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final caps = context.watch<CapabilitiesBloc>().state.data;
    final allowed = caps?.tabs ?? _allTabs;
    final entries = <_ShellTab>[
      if (allowed.contains('home')) const _ShellTab('Home', Icons.home_outlined, Icons.home, HomeScreen()),
      if (allowed.contains('inbox')) const _ShellTab('Inbox', Icons.inbox_outlined, Icons.inbox, InboxScreen()),
      if (allowed.contains('wall')) const _ShellTab('Wall', Icons.forum_outlined, Icons.forum, WallScreen()),
      if (allowed.contains('me')) const _ShellTab('Me', Icons.person_outline, Icons.person, MeScreen()),
      if (allowed.contains('team')) const _ShellTab('My Team', Icons.groups_outlined, Icons.groups, MyTeamScreen()),
    ];
    final safe = entries.isEmpty
        ? const [_ShellTab('Home', Icons.home_outlined, Icons.home, HomeScreen())]
        : entries;
    final index = _index.clamp(0, safe.length - 1);
    return Scaffold(
      body: IndexedStack(index: index, children: [for (final t in safe) t.body]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in safe)
            NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
        ],
      ),
    );
  }
}

class _ShellTab {
  const _ShellTab(this.label, this.icon, this.selectedIcon, this.body);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget body;
}

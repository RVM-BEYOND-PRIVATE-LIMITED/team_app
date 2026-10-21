import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
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

  /// Tabs whose screen has been opened at least once. Everything in an
  /// [IndexedStack] is built, so opening all five at launch would fire every
  /// tab's network calls (Wall included) before the person ever sees them —
  /// one failing call then freezes a debug run on a screen they never opened.
  final Set<String> _opened = {'home'};

  static const _allTabs = ['home', 'inbox', 'wall', 'me', 'team'];

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<CapabilitiesBloc>()..add(const LoadRequested()),
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final caps = context.watch<CapabilitiesBloc>().state.data;
    final allowed = caps?.tabs ?? _allTabs;
    final entries = <_ShellTab>[
      if (allowed.contains('home'))
        const _ShellTab(
            'Home', Icons.home_outlined, Icons.home_rounded, HomeScreen()),
      if (allowed.contains('inbox'))
        const _ShellTab(
            'Inbox', Icons.inbox_outlined, Icons.inbox_rounded, InboxScreen()),
      if (allowed.contains('wall'))
        const _ShellTab(
            'Wall', Icons.forum_outlined, Icons.forum_rounded, WallScreen()),
      if (allowed.contains('me'))
        const _ShellTab('Me', Icons.person_outline_rounded,
            Icons.person_rounded, MeScreen()),
      if (allowed.contains('team'))
        const _ShellTab('My Team', Icons.groups_outlined, Icons.groups_rounded,
            MyTeamScreen()),
    ];
    final safe = entries.isEmpty
        ? const [
            _ShellTab(
                'Home', Icons.home_outlined, Icons.home_rounded, HomeScreen())
          ]
        : entries;
    final index = _index.clamp(0, safe.length - 1);
    // The selected tab always builds; the rest wait until first opened.
    final open = {..._opened, safe[index].label};
    return Scaffold(
      backgroundColor: RvmColors.ivory,
      body: IndexedStack(
        index: index,
        children: [
          for (final t in safe)
            open.contains(t.label) ? t.body : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: _TeamBottomNav(
        index: index,
        tabs: safe,
        onSelected: (i) => setState(() {
          _index = i;
          _opened.add(safe[i].label);
        }),
      ),
    );
  }
}

/// The reference's flat, airy tab bar: line icons over 10px labels, a warm
/// clay active state and a hairline top border instead of a raised surface.
class _TeamBottomNav extends StatelessWidget {
  const _TeamBottomNav(
      {required this.index, required this.tabs, required this.onSelected});

  final int index;
  final List<_ShellTab> tabs;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
        color: RvmColors.white,
        border: Border(top: BorderSide(color: RvmColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onSelected(i),
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          i == index ? tabs[i].selectedIcon : tabs[i].icon,
                          size: 21,
                          color: i == index ? RvmColors.clay : RvmColors.subtle,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tabs[i].label,
                          style: text.labelSmall?.copyWith(
                            fontSize: 9.5,
                            letterSpacing: 0.1,
                            fontWeight:
                                i == index ? FontWeight.w700 : FontWeight.w500,
                            color:
                                i == index ? RvmColors.clay : RvmColors.subtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
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

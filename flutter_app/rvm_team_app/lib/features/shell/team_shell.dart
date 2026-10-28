import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app_crash.dart';
import '../../auth/team_permissions.dart';
import '../../bloc/team_auth_bloc.dart';
import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../home/home_screen.dart';
import '../inbox/inbox_screen.dart';
import '../me/me_screen.dart';
import '../my_team/my_team_screen.dart';
import '../wall/wall_screen.dart';

/// The five Keka-style tabs: Home · Inbox · Wall · My Team · Me.
///
/// The shell checks the ESS capabilities BEFORE it builds any tab. A login that
/// is not linked to an `hr_employees` record (an HR account that has no employee
/// record yet) gets one clear explanation, not a Home screen whose five cards
/// each throw the same 403. The check itself is non-throwing, so it cannot stop
/// the debugger on an expected `NOT_LINKED`.
class TeamShell extends StatefulWidget {
  const TeamShell({super.key});

  @override
  State<TeamShell> createState() => _TeamShellState();
}

class _TeamShellState extends State<TeamShell> {
  int _index = 0;

  /// Tabs whose screen has been opened at least once. Everything in an
  /// [IndexedStack] is built, so opening all five at launch would fire every
  /// tab's network calls before the person ever sees them.
  final Set<String> _opened = {'home'};

  static const _allTabs = ['home', 'inbox', 'wall', 'team', 'me'];

  late final CapabilitiesBloc _caps = getIt<CapabilitiesBloc>();
  bool _loading = true;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _caps.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    }
    try {
      final result = await getIt<EssRepository>().capabilitiesSafe();
      if (!mounted) return;
      if (result.data != null) {
        _caps.add(LoadSucceeded(result.data!));
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _loading = false;
        _failure = result.failure ?? const UnknownFailure();
      });
    } catch (e) {
      // capabilitiesSafe itself never throws, but a DI or state error here
      // must still land on the retry screen, never a dead loader.
      CrashReporter.record(e, null, reason: 'shell:capabilities');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failure =
            const UnknownFailure('Could not check your access. Try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: RvmColors.ivory,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Checking your access…', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }
    final caps = _caps.state.data;
    if (_failure != null || caps == null) {
      return _AccessError(
        failure: _failure ?? const UnknownFailure(),
        onRetry: _load,
      );
    }
    return BlocProvider.value(
      value: _caps,
      child: Builder(builder: (context) => _tabs(context, caps)),
    );
  }

  Widget _tabs(BuildContext context, EssCapabilities caps) {
    final identity = context.watch<TeamAuthBloc>().state.identity;
    final attendance = identity?.attendance == true;
    final teaching = TeamPermissions.forRole(identity?.role ?? AppRole.unknown)
        .canSeeFacultyWork;
    final allowed = caps.tabs.isEmpty ? _allTabs : caps.tabs;
    final entries = <_ShellTab>[
      if (allowed.contains('home'))
        const _ShellTab(
            'Home', Icons.home_outlined, Icons.home_rounded, HomeScreen()),
      // Priority tasks are a Scheduler read; an attendance-only punch token is
      // refused there. The Inbox tab is for portal sign-ins. Teaching roles use
      // it to mark their batches instead (KP, 27 Oct).
      if (!attendance && allowed.contains('inbox'))
        _ShellTab(
            teaching ? 'Attendance' : 'Inbox',
            teaching ? Icons.fact_check_outlined : Icons.inbox_outlined,
            teaching ? Icons.fact_check_rounded : Icons.inbox_rounded,
            const InboxScreen()),
      if (allowed.contains('wall'))
        const _ShellTab(
            'Wall', Icons.forum_outlined, Icons.forum_rounded, WallScreen()),
      if (allowed.contains('team'))
        const _ShellTab('My Team', Icons.groups_outlined, Icons.groups_rounded,
            MyTeamScreen()),
      if (allowed.contains('me'))
        const _ShellTab('Me', Icons.person_outline_rounded,
            Icons.person_rounded, MeScreen()),
    ];
    final safe = entries.isEmpty
        ? const [
            _ShellTab(
                'Home', Icons.home_outlined, Icons.home_rounded, HomeScreen())
          ]
        : entries;
    final index = _index.clamp(0, safe.length - 1);
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

/// Shown instead of the tabs when the ESS refuses the capabilities call. The
/// usual case is `NOT_LINKED`: the login exists but no employee record points
/// at it yet, so every ESS endpoint would answer the same 403.
class _AccessError extends StatelessWidget {
  const _AccessError({required this.failure, required this.onRetry});
  final Failure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: RvmColors.ivory,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: RvmColors.ironwood,
                    borderRadius: BorderRadius.circular(RvmRadii.lg),
                  ),
                  child: const Icon(Icons.link_off_rounded,
                      color: RvmColors.ivory, size: 32),
                ),
                const SizedBox(height: 20),
                Text('Team RVM',
                    style: text.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(
                  failure.message,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: RvmColors.muted),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () =>
                      context.read<TeamAuthBloc>().add(const TeamSignedOut()),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
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

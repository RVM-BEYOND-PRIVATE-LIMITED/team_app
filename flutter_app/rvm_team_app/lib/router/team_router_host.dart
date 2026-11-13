import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/team_auth_bloc.dart';
import '../bloc/team_modules_bloc.dart';
import 'app_router.dart';
import 'module_routes.dart';
import 'sensitive_routes.dart';

/// The app's router ([createRouter]) and the listeners that keep it in step
/// with the session and the open modules (team_app #50, items 5 and 7b).
/// `TeamApp` (main.dart) builds its `MaterialApp.router` through [builder],
/// and the tests pump this same widget, so the wiring they check is the app's.
///
///  * The session changed: the guards run again (splash → sign-in → shell).
///  * Sign-out, or a session that ended: the modules are cleared, so nothing
///    stays open, an answer still on its way is dropped, and the next sign-in
///    asks for its own.
///  * The open modules changed: the guards run again, so a module route on
///    screen that an answer closed falls back to `/home`. A change that only
///    flips `dry_run`, or an answer with the same modules, does not run them.
///  * A module route refused before this sign-in's modules have answered (a
///    push tap that opens the app, whose route is sent as soon as the sign-in
///    is restored) is held. When the answer comes and opens its module, the
///    app goes there; otherwise it is dropped. Sign-out drops it too. Nothing
///    is held for an attendance-only sign-in, which never asks.
class TeamRouterHost extends StatefulWidget {
  const TeamRouterHost({
    super.key,
    required this.auth,
    required this.modules,
    required this.builder,
    this.navigatorKey,
    this.secureRoster = secureRosterOn,
  });

  final TeamAuthBloc auth;
  final TeamModulesBloc modules;
  final GlobalKey<NavigatorState>? navigatorKey;
  final bool secureRoster;

  /// The app around [router], usually a `MaterialApp.router`.
  final Widget Function(BuildContext context, GoRouter router) builder;

  @override
  State<TeamRouterHost> createState() => _TeamRouterHostState();
}

class _TeamRouterHostState extends State<TeamRouterHost> {
  late final GoRouter _router = createRouter(
    widget.auth,
    navigatorKey: widget.navigatorKey,
    modules: () => widget.modules.state.modules.open,
    onModuleBlocked: _hold,
    secureRoster: widget.secureRoster,
  );

  /// The module location refused before the modules answered, if any.
  String? _held;

  /// Keeps [location] when the modules of this sign-in may still open it.
  void _hold(String location) {
    if (widget.modules.state.status == TeamModulesStatus.ready ||
        widget.auth.state.identity?.attendance == true) {
      return;
    }
    _held = location;
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<TeamAuthBloc, TeamAuthState>(
          bloc: widget.auth,
          listenWhen: (p, c) => p.status != c.status,
          listener: (_, state) {
            if (state.status != TeamAuthStatus.authenticated) {
              _held = null;
              widget.modules.add(const TeamModulesCleared());
            }
            _router.refresh();
          },
        ),
        BlocListener<TeamModulesBloc, TeamModulesState>(
          bloc: widget.modules,
          listenWhen: (p, c) =>
              !setEquals(p.modules.open, c.modules.open) ||
              (_held != null && c.status == TeamModulesStatus.ready),
          listener: (_, state) {
            final held =
                state.status == TeamModulesStatus.ready ? _held : null;
            if (held != null) _held = null;
            if (held != null &&
                !moduleBlockedLocation(
                    Uri.parse(held).path, state.modules.open)) {
              _router.go(held);
            } else {
              _router.refresh();
            }
          },
        ),
      ],
      child: Builder(builder: (context) => widget.builder(context, _router)),
    );
  }
}

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/team_auth_bloc.dart';
import '../bloc/team_modules_bloc.dart';

/// The app-wide listeners that keep the router's module guard in step with
/// [modules] (team_app #50, items 5 and 7b). `TeamApp` (main.dart) puts them
/// above the router, beside its own sign-in listener.
///
///  * Sign-out, or a session that ended: the modules are cleared, so nothing
///    stays open, an answer still on its way is dropped, and the next sign-in
///    asks for its own.
///  * The open modules changed: [router] runs its guards again, so a module
///    route on screen that is no longer open falls back to `/home`. A change
///    that only flips `dry_run`, or a refresh with the same answer, does not
///    run them.
List<BlocListener> moduleGuardListeners({
  required GoRouter router,
  required TeamModulesBloc modules,
}) =>
    [
      BlocListener<TeamAuthBloc, TeamAuthState>(
        listenWhen: (p, c) =>
            p.status != c.status && c.status != TeamAuthStatus.authenticated,
        listener: (_, __) => modules.add(const TeamModulesCleared()),
      ),
      BlocListener<TeamModulesBloc, TeamModulesState>(
        bloc: modules,
        listenWhen: (p, c) => !setEquals(p.modules.open, c.modules.open),
        listener: (_, __) => router.refresh(),
      ),
    ];

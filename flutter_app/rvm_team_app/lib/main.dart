import 'package:core_auth/core_auth.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'bloc/connectivity_bloc.dart';
import 'bloc/team_auth_bloc.dart';
import 'features/startup/version_gate.dart';
import 'injection.dart';
import 'router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hydrate the session, wire the graph, probe the stored JWT (claims only).
  final session = AuthSession();
  await session.load();
  configureDependencies(session);
  getIt<TeamAuthBloc>().add(const TeamAuthProbeRequested());

  runApp(const TeamApp());
}

class TeamApp extends StatefulWidget {
  const TeamApp({super.key});

  @override
  State<TeamApp> createState() => _TeamAppState();
}

class _TeamAppState extends State<TeamApp> {
  final TeamAuthBloc _auth = getIt<TeamAuthBloc>();
  late final GoRouter _router = createRouter(_auth);

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _auth),
        BlocProvider.value(value: getIt<ConnectivityBloc>()),
      ],
      child: BlocListener<TeamAuthBloc, TeamAuthState>(
        listenWhen: (p, c) => p.status != c.status,
        listener: (_, __) => _router.refresh(),
        child: MaterialApp.router(
          title: 'Team RVM',
          debugShowCheckedModeBanner: false,
          theme: RvmTheme.light(seed: RvmColors.teamSeed),
          darkTheme: RvmTheme.dark(seed: RvmColors.teamSeed),
          themeMode: ThemeMode.system,
          builder: (context, child) => VersionGate(child: child ?? const SizedBox.shrink()),
          routerConfig: _router,
        ),
      ),
    );
  }
}

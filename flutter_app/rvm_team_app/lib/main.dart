import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:core_auth/core_auth.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'app_bloc_observer.dart';
import 'app_crash.dart';
import 'app_feedback.dart';
import 'bloc/connectivity_bloc.dart';
import 'bloc/team_auth_bloc.dart';
import 'features/startup/version_gate.dart';
import 'injection.dart';
import 'router/app_router.dart';

void main() {
  // Every async gap is guarded. A missed API refusal, a plugin failure or a
  // build error ends in a readable message, never a silent crash.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    Bloc.observer = const AppBlocObserver();
    await CrashReporter.init();
    FlutterError.onError = (details) {
      CrashReporter.flutterError(details);
      showAppMessage('Something went wrong. Please try again.');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashReporter.record(error, stack, fatal: true);
      showAppMessage('Something went wrong. Please try again.');
      return true;
    };
    ErrorWidget.builder = (_) => const _SafeErrorView();

    // Hydrate the session, wire the graph, probe the stored JWT (claims only).
    final session = AuthSession();
    await session.load();
    configureDependencies(session);
    getIt<TeamAuthBloc>().add(const TeamAuthProbeRequested());

    // D5: register for push when a token is available (Firebase is not configured yet, ADR-0016).
    const pushToken = String.fromEnvironment('FCM_TOKEN');
    if (pushToken.isNotEmpty) unawaited(registerPushToken(pushToken));

    runApp(const TeamApp());
  }, (error, stack) {
    CrashReporter.record(error, stack, fatal: true);
    showAppMessage('Something went wrong. Please try again.');
  });
}

/// Shown in place of the red framework error screen when a widget build fails.
class _SafeErrorView extends StatelessWidget {
  const _SafeErrorView();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: RvmColors.ivory,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 40, color: RvmColors.danger),
                const SizedBox(height: 12),
                Text(
                  'Something went wrong. Please reopen the app.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TeamApp extends StatefulWidget {
  const TeamApp({super.key});

  @override
  State<TeamApp> createState() => _TeamAppState();
}

class _TeamAppState extends State<TeamApp> {
  final TeamAuthBloc _auth = getIt<TeamAuthBloc>();
  late final GoRouter _router =
      createRouter(_auth, navigatorKey: rootNavigatorKey);

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
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          debugShowCheckedModeBanner: false,
          // The whole design system (ivory scaffolds, white cards, clay
          // surfaces) is authored for the light palette: following the system
          // into dark mode mixes white cards with dark fills and washed-out
          // text (OnePlus 12R, issue14). Locked to light so every device shows
          // the same colors. Revisit only with a full dark-mode audit.
          theme: RvmTheme.light(seed: RvmColors.clay),
          themeMode: ThemeMode.light,
          builder: (context, child) =>
              VersionGate(child: child ?? const SizedBox.shrink()),
          routerConfig: _router,
        ),
      ),
    );
  }
}

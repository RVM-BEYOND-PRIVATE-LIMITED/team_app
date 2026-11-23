import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:core_auth/core_auth.dart';
import 'package:core_network/core_network.dart' show ApiEnvironment;
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_bloc_observer.dart';
import 'app_crash.dart';
import 'app_feedback.dart';
import 'bloc/connectivity_bloc.dart';
import 'bloc/team_auth_bloc.dart';
import 'bloc/team_modules_bloc.dart';
import 'data/notification_permission.dart';
import 'features/feedback/feedback_overlay.dart';
import 'features/startup/version_gate.dart';
import 'injection.dart';
import 'push/push_service.dart';
import 'router/team_router_host.dart';
import 'theme/theme_cubit.dart';
import 'widgets/env_ribbon.dart';

void main() {
  // Every async gap is guarded. A missed API refusal, a plugin failure or a
  // build error ends in a readable message, never a silent crash.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    Bloc.observer = const AppBlocObserver();
    await CrashReporter.init();
    FlutterError.onError = (details) {
      if (_isImageNoise(details.exception)) {
        // Dead avatar/photo URL (offline DNS like issue13's Supabase host,
        // expired signed link). UI already shows the initial via errorBuilder
        // (issue22); reporting it as fatal + toasting would look like a crash.
        CrashReporter.record(details.exception, details.stack,
            reason: 'image-load (handled by fallback)');
        return;
      }
      CrashReporter.flutterError(details);
      showAppMessage('Something went wrong. Please try again.');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      if (_isImageNoise(error)) {
        CrashReporter.record(error, stack,
            reason: 'image-load (handled by fallback)');
        return true;
      }
      CrashReporter.record(error, stack, fatal: true);
      showAppMessage('Something went wrong. Please try again.');
      return true;
    };
    ErrorWidget.builder = (_) => const _SafeErrorView();

    // Hydrate the session, wire the graph, probe the stored JWT (claims only).
    final session = AuthSession();
    await session.load().timeout(const Duration(seconds: 5), onTimeout: () {});
    configureDependencies(session);
    getIt<TeamAuthBloc>().add(const TeamAuthProbeRequested());

    // Failsafe: a secure-storage or restore call that never answers on one
    // device must not leave the app on the splash forever. Once the probe has
    // had time to run, show the sign-in screen instead.
    Timer(const Duration(seconds: 10), () {
      if (getIt<TeamAuthBloc>().state.status == TeamAuthStatus.unknown) {
        getIt<TeamAuthBloc>().add(const TeamSessionExpired());
      }
    });

    // Firebase Cloud Messaging: permission, token, foreground display (text and
    // image), background data messages, and notification-tap routing. Sign-in
    // attaches the token to the employee via /push-devices (see TeamApp below).
    unawaited(PushService.instance.init());

    runApp(const TeamApp());
  }, (error, stack) {
    if (_isImageNoise(error)) {
      CrashReporter.record(error, stack,
          reason: 'image-load (handled by fallback)');
      return;
    }
    CrashReporter.record(error, stack, fatal: true);
    showAppMessage('Something went wrong. Please try again.');
  });
}

/// Image-load noise (DNS for a photo host, expired signed URL, 404) is
/// expected offline and already has a UI fallback (initial avatar). It must
/// never toast or count as a fatal crash (issue13 text on issue22 screen).
bool _isImageNoise(Object error) {
  final s = error.toString();
  return s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('NetworkImage') ||
      s.contains('ImageInfo') ||
      s.contains('HttpException');
}

/// Shown in place of the red framework error screen when a widget build fails.
class _SafeErrorView extends StatelessWidget {
  const _SafeErrorView();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: p.canvas,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 40, color: p.danger),
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

  /// The staff modules open to the person (team_app #50 item 5). The router's
  /// module guard reads it ([TeamRouterHost], item 7b): nothing is open before
  /// its first answer, so every module route falls back to /home, as before.
  final TeamModulesBloc _modules = getIt<TeamModulesBloc>();
  final ThemeCubit _theme = getIt<ThemeCubit>();
  late final AppLifecycleListener _themeLifecycle;

  static const _notificationPermission = NotificationPermission();
  bool _askedNotifications = false;

  @override
  void initState() {
    super.initState();
    if (_auth.state.status == TeamAuthStatus.authenticated) {
      _askNotificationPermission();
      unawaited(PushService.instance.onSignedIn());
      unawaited(_theme.load());
    }
    _themeLifecycle = AppLifecycleListener(
      onResume: () {
        if (_auth.state.status == TeamAuthStatus.authenticated) {
          unawaited(_theme.resume());
        }
      },
    );
  }

  @override
  void dispose() {
    _themeLifecycle.dispose();
    super.dispose();
  }

  /// Android 13+ hides notification alerts until POST_NOTIFICATIONS is granted.
  /// Ask once per launch, after sign-in, without blocking the UI or the router.
  void _askNotificationPermission() {
    if (_askedNotifications) return;
    _askedNotifications = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_notificationPermission.requestIfNeeded());
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _auth),
        BlocProvider.value(value: getIt<ConnectivityBloc>()),
        BlocProvider.value(value: _modules),
        BlocProvider.value(value: _theme),
      ],
      child: BlocListener<TeamAuthBloc, TeamAuthState>(
        listenWhen: (p, c) => p.status != c.status,
        listener: (_, state) {
          if (state.status == TeamAuthStatus.authenticated) {
            _askNotificationPermission();
            unawaited(PushService.instance.onSignedIn());
            unawaited(_theme.load());
          } else if (state.status == TeamAuthStatus.unauthenticated) {
            unawaited(_theme.signOut());
          }
        },
        // The router: its guards run again on every session change, and its
        // module guard follows the modules bloc (#50 items 5 and 7b).
        child: BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, theme) => TeamRouterHost(
            auth: _auth,
            modules: _modules,
            navigatorKey: rootNavigatorKey,
            builder: (context, router) => MaterialApp.router(
              title: 'Team RVM',
              scaffoldMessengerKey: rootScaffoldMessengerKey,
              debugShowCheckedModeBanner: false,
              // The switch in Me decides; while the server's theme switch is
              // closed ThemeCubit keeps themeMode at Light (#115/#121).
              theme: RvmTheme.light(seed: RvmColors.clay),
              darkTheme: RvmTheme.dark(seed: RvmColors.clay),
              themeMode: theme.mode,
              // The TEST SERVER ribbon (#60) is off unless
              // SHOW_ENV_RIBBON=true, and never shows against the live servers.
              builder: (context, child) => FeedbackOverlay(
                router: router,
                child: EnvRibbon(
                  environment: getIt<ApiEnvironment>(),
                  child: VersionGate(child: child ?? const SizedBox.shrink()),
                ),
              ),
              routerConfig: router,
            ),
          ),
        ),
      ),
    );
  }
}

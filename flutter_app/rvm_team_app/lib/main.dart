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
import 'data/notification_permission.dart';
import 'features/startup/version_gate.dart';
import 'injection.dart';
import 'push/push_service.dart';
import 'router/app_router.dart';

void main() {
  // Every async gap is guarded. A missed API refusal, a plugin failure or a
  // build error ends in a readable message, never a silent crash.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    Bloc.observer = const AppBlocObserver();
    unawaited(CrashReporter.init());
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

  static const _notificationPermission = NotificationPermission();
  bool _askedNotifications = false;

  @override
  void initState() {
    super.initState();
    if (_auth.state.status == TeamAuthStatus.authenticated) {
      _askNotificationPermission();
      unawaited(PushService.instance.onSignedIn());
    }
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
      ],
      child: BlocListener<TeamAuthBloc, TeamAuthState>(
        listenWhen: (p, c) => p.status != c.status,
        listener: (_, state) {
          _router.refresh();
          if (state.status == TeamAuthStatus.authenticated) {
            _askNotificationPermission();
            unawaited(PushService.instance.onSignedIn());
          }
        },
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

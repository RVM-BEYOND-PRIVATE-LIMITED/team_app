import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:local_auth/local_auth.dart';

import '../bloc/team_auth_bloc.dart';
import '../data/repositories/team_stage2_repository.dart';
import '../platform/secure_window.dart';

/// Blocks screenshots while [child] is on screen (team_app #52, item 1).
///
/// It holds the window's block ([SecureWindow]) only while its route is the
/// one on screen:
///  * on from its first frame, and through its own push and pop animations,
///    while the screen can still be seen;
///  * still on under a dialog or a bottom sheet, which leave the screen
///    visible behind them;
///  * off once an opaque route has covered it (the Navigator stops the tickers
///    of a route nobody can see), and on again when that route is popped;
///  * off while [enabled] is false, which is how a shell tab says it is not
///    the selected one (an IndexedStack keeps every opened tab built);
///  * off when it leaves the tree.
///
/// Scopes are counted, so a sensitive screen pushed over a sensitive tab, or
/// two sensitive screens crossing in a transition, never drop the block in
/// between, and a screen that is not sensitive never turns it on.
class SecureScope extends StatefulWidget {
  const SecureScope({
    super.key,
    required this.child,
    this.enabled = true,
    this.window,
  });

  final Widget child;

  /// False keeps the window as it is. A shell tab passes "is selected".
  final bool enabled;

  /// The window to hold; [SecureWindow.instance] unless a test passes one.
  final SecureWindow? window;

  @override
  State<SecureScope> createState() => _SecureScopeState();
}

class _SecureScopeState extends State<SecureScope> {
  /// The window this scope holds the block on, or null while it holds none.
  SecureWindow? _held;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SecureScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _hold(null);
    super.dispose();
  }

  /// TickerMode is false for a route an opaque route covers, so reading it
  /// also rebuilds this scope when that changes.
  void _sync() => _hold(widget.enabled && TickerMode.of(context)
      ? (widget.window ?? SecureWindow.instance)
      : null);

  void _hold(SecureWindow? window) {
    if (identical(window, _held)) return;
    _held?.release();
    _held = window;
    window?.acquire();
  }

  @override
  Widget build(BuildContext context) =>
      _IdleLock(enabled: widget.enabled, child: widget.child);
}

/// The 30-minute idle lock (team_app #52, item 2). It counts time in the
/// foreground and in the background; a sensitive screen covers itself with
/// this overlay at the limit, and unlocking asks the phone's own screen lock.
/// The child stays mounted underneath, so a half-filled form survives.
class _IdleLock extends StatefulWidget {
  const _IdleLock({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  State<_IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends State<_IdleLock> {
  static const _limit = Duration(minutes: 30);
  DateTime _lastActive = DateTime.now();
  bool _locked = false;
  Timer? _ticker;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) => _check());
    _lifecycle = AppLifecycleListener(onShow: _check);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _touch() {
    if (!_locked) _lastActive = DateTime.now();
  }

  void _check() {
    if (!mounted || !widget.enabled || _locked) return;
    if (DateTime.now().difference(_lastActive) >= _limit) {
      setState(() => _locked = true);
    }
  }

  Future<void> _unlock() async {
    final auth = LocalAuthentication();
    bool ok = false;
    try {
      ok = await auth.authenticate(
        localizedReason: 'Unlock Team RVM',
        options: const AuthenticationOptions(
            biometricOnly: false, stickyAuth: true),
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      // No screen lock, or the person cancelled: signing in again is the only
      // way back (the issue's default for a phone with no screen lock).
      final getIt = GetIt.instance;
      if (getIt.isRegistered<TeamAuthBloc>()) {
        getIt<TeamAuthBloc>().add(const TeamSignedOut());
      }
      return;
    }
    final getIt = GetIt.instance;
    if (getIt.isRegistered<TeamStage2Repository>()) {
      try {
        await getIt<TeamStage2Repository>().unlock(
            key: 'unlock-${DateTime.now().microsecondsSinceEpoch}');
      } on Failure {
        // The overlay still opens locally; the server decides on the next call.
      }
    }
    if (!mounted) return;
    setState(() {
      _locked = false;
      _lastActive = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) {
      return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _touch(),
          child: widget.child);
    }
    final p = context.palette;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: Material(
            color: p.canvas,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 56, color: p.primary),
                    const SizedBox(height: 14),
                    Text('Team RVM is locked',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Unlock with your fingerprint, face or PIN.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                        onPressed: _unlock,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Unlock')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

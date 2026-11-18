import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/team_auth_bloc.dart';
import '../../domain/team_stage2_models.dart';
import '../../widgets/blocked_state.dart';
import '../../widgets/states.dart';
import '../stage2/stage2_shared.dart';

/// Wraps a sensitive module with the server's access answer (#52 item 7):
/// waiting for HR, signed in elsewhere, not punched in, or outside the shift.
/// It checks again when the person comes back from punching in. The server is
/// still the authority; this is the friendly half. With no repository (a
/// widget test) it shows the screen as before.
class SensitiveGate extends StatefulWidget {
  const SensitiveGate({super.key, required this.child});
  final Widget child;
  @override
  State<SensitiveGate> createState() => _SensitiveGateState();
}

class _SensitiveGateState extends State<SensitiveGate> {
  static TeamAccess? _cached;
  static DateTime? _cachedAt;
  TeamAccess? _access;
  Failure? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final repo = stage2RepositoryOrNull();
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    final cachedAt = _cachedAt;
    if (_cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(seconds: 45)) {
      setState(() {
        _access = _cached;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final access = await repo.access();
      _cached = access;
      _cachedAt = DateTime.now();
      if (!mounted) return;
      setState(() {
        _access = access;
        _loading = false;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (stage2RepositoryOrNull() == null) return widget.child;
    if (_loading && _access == null) {
      return const Material(child: AppLoading(label: 'Checking access…'));
    }
    if (_failure is UnauthorizedFailure) {
      return _SignedOut(failure: _failure!);
    }
    final access = _access;
    if (access == null) {
      final failure = _failure;
      if (failure != null) {
        final blocked = blockedReasonFor(failure);
        if (blocked != null) {
          return BlockedState(
            reason: blocked,
            message: failure.message,
            actionLabel: 'Try again',
            onAction: _check,
          );
        }
        return AppError(message: failure.message, onRetry: _check);
      }
      return widget.child;
    }
    if (access.devicePending) {
      return _Wait(
          icon: Icons.phone_android,
          title: 'This phone is waiting for HR',
          message: 'HR has to approve this phone before this screen opens.',
          onRetry: _check,
          onSignOut: _signOut);
    }
    if (!access.sessionLive || access.sessionSuperseded) {
      return _Wait(
          icon: Icons.devices_other,
          title: 'Signed in on another phone',
          message: 'This sign-in ended. Sign in again here.',
          onRetry: _check,
          onSignOut: _signOut);
    }
    if (!access.punchedIn) {
      return BlockedState(
        reason: BlockedReason.notPunchedIn,
        actionLabel: 'Punch in',
        actionIcon: Icons.fingerprint,
        onAction: () async {
          await context.push('/me/punch');
          _cached = null;
          _check();
        },
      );
    }
    if (!access.onShift) {
      return BlockedState(
        reason: BlockedReason.outsideShift,
        actionLabel: 'Check again',
        onAction: _check,
      );
    }
    return widget.child;
  }

  void _signOut() {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<TeamAuthBloc>()) {
      getIt<TeamAuthBloc>().add(const TeamSignedOut());
    }
  }
}

class _Wait extends StatelessWidget {
  const _Wait({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });
  final IconData icon;
  final String title, message;
  final VoidCallback onRetry, onSignOut;

  @override
  Widget build(BuildContext context) => Material(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 52, color: context.palette.primary),
                const SizedBox(height: 12),
                Text(title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: const Text('Check again')),
                TextButton(onPressed: onSignOut, child: const Text('Sign out')),
              ],
            ),
          ),
        ),
      );
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.failure});
  final Failure failure;
  @override
  Widget build(BuildContext context) => Material(
        child: Center(
            child: Text(failure.message, textAlign: TextAlign.center)),
      );
}

import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app_version.dart';
import '../../bloc/team_auth_bloc.dart';
import '../../data/repositories/ess_repository.dart';
import '../../injection.dart';

/// Advisory version gate (task K2). The ESS `/health` reports the minimum and
/// latest app versions; below the minimum, an update is forced (a phone that is
/// too old must not keep punching). A failure to read health never blocks the
/// app — it just skips the gate.
class VersionGate extends StatefulWidget {
  const VersionGate({super.key, required this.child});
  final Widget child;

  @override
  State<VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends State<VersionGate> {
  bool _checking = false;
  bool _checked = false;
  bool _mustUpdate = false;
  String? _minVersion;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final health = await getIt<EssRepository>().health();
      final min = health.minAppVersion;
      if (!mounted) return;
      setState(() {
        _checking = false;
        _minVersion = min;
        _mustUpdate = min != null && _isOlder(appVersion, min);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A signed-out launch must not call the ESS at all (a cold-start request can
    // hit the resolver before the OS network is ready and surface a raw
    // `Failed host lookup`). Check once, only after a session exists.
    final authenticated = context.select<TeamAuthBloc, bool>(
      (bloc) => bloc.state.status == TeamAuthStatus.authenticated,
    );
    if (authenticated && !_checked) {
      _checked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _check();
      });
    }

    if (!_mustUpdate) return widget.child;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(RvmSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.system_update_alt, size: 48),
              const SizedBox(height: RvmSpacing.md),
              Text('Update required',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: RvmSpacing.sm),
              Text(
                'This version of Team RVM is no longer supported. Please update to '
                'continue (v$_minVersion or newer).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: RvmSpacing.lg),
              FilledButton.icon(
                onPressed: _checking ? null : _check,
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Simple dotted-numeric comparison (ignores any `+build` suffix).
  static bool _isOlder(String current, String min) {
    final a = current
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final b = min
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x < y;
    }
    return false;
  }
}

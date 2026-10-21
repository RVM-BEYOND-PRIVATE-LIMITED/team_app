import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../bloc/connectivity_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'team_kit.dart';

/// Centered progress for a loading screen.
class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: RvmColors.clay),
          ),
          if (label != null) ...[
            const SizedBox(height: 12),
            Text(label!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Centered error with a retry, showing the REAL cause.
class AppError extends StatelessWidget {
  const AppError({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TeamIconBadge(
              icon: Icons.cloud_off_outlined,
              color: RvmColors.danger,
              background: RvmColors.dangerSoft,
              size: 56,
              iconSize: 26,
              radius: 18,
            ),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                  onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centered empty state.
class AppEmpty extends StatelessWidget {
  const AppEmpty(
      {super.key, required this.message, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TeamIconBadge(
              icon: icon,
              color: RvmColors.muted,
              background: RvmColors.cream,
              size: 56,
              iconSize: 25,
              radius: 18,
            ),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 12, color: RvmColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// A thin bar shown while the device is offline.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityBloc, ConnectivityState>(
      buildWhen: (a, b) => a.online != b.online,
      builder: (context, state) {
        if (state.online) return const SizedBox.shrink();
        return Material(
          color: RvmColors.dangerSoft,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 14, color: RvmColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('No internet connection',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 11, color: RvmColors.danger)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

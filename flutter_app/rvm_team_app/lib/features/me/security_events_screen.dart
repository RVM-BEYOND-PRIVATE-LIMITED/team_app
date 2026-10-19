import 'package:core_bloc/core_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';

/// Recent security activity for this account (`GET /api/me/security-events`).
class SecurityEventsScreen extends StatelessWidget {
  const SecurityEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SecurityEventsBloc>()..add(const LoadRequested()),
      child: Scaffold(
        appBar: AppBar(title: const Text('Security activity')),
        body: BlocBuilder<SecurityEventsBloc, LoadState<List<SecurityEvent>>>(
          builder: (context, state) {
            return switch (state.status) {
              LoadStatus.loading || LoadStatus.initial => const AppLoading(),
              LoadStatus.failure => AppError(
                  message: state.failure?.message ?? 'Could not load security activity.',
                  onRetry: () => context.read<SecurityEventsBloc>().add(const LoadRefreshed()),
                ),
              LoadStatus.empty => const AppEmpty(message: 'No security activity recorded yet.', icon: Icons.history),
              LoadStatus.success => RefreshIndicator(
                  onRefresh: () async => context.read<SecurityEventsBloc>().add(const LoadRefreshed()),
                  child: ListView.separated(
                    itemCount: state.data!.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = state.data![i];
                      return ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: Text(e.event.replaceAll('_', ' ')),
                        subtitle: Text([
                          if (e.createdAt != null) e.createdAt!.toLocal().toString(),
                          if (e.ip != null) e.ip!,
                        ].join(' · ')),
                      );
                    },
                  ),
                ),
            };
          },
        ),
      ),
    );
  }
}

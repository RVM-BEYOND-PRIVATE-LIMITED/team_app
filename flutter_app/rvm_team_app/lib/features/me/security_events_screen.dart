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
            final data = state.data;
            Widget list() => RefreshIndicator(
                  onRefresh: () async => context
                      .read<SecurityEventsBloc>()
                      .add(const LoadRefreshed()),
                  child: ListView.separated(
                    itemCount: data!.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = data[i];
                      return ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: Text(e.event.replaceAll('_', ' ')),
                        subtitle: Text([
                          if (e.ip != null) e.ip!,
                          if (e.createdAt != null)
                            MaterialLocalizations.of(context)
                                .formatShortDate(e.createdAt!.toLocal()),
                        ].join(' · ')),
                      );
                    },
                  ),
                );
            if (state.status == LoadStatus.initial ||
                state.status == LoadStatus.loading) {
              return data == null || data.isEmpty ? const AppLoading() : list();
            }
            if (state.status == LoadStatus.failure) {
              return data == null || data.isEmpty
                  ? AppError(
                      message: state.failure?.message ??
                          'Could not load security activity.',
                      onRetry: () => context
                          .read<SecurityEventsBloc>()
                          .add(const LoadRefreshed()),
                    )
                  : list();
            }
            if (state.status == LoadStatus.empty ||
                data == null ||
                data.isEmpty) {
              return const AppEmpty(
                  message: 'No security activity recorded yet.',
                  icon: Icons.history);
            }
            return list();
          },
        ),
      ),
    );
  }
}

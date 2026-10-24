import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import 'bloc/sessions_bloc.dart';

/// A3: the phones this account is still signed in on ("sign out everywhere",
/// one device at a time).
class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SessionsBloc>()..add(const SessionsLoadRequested()),
      child: const _SessionsView(),
    );
  }
}

class _SessionsView extends StatelessWidget {
  const _SessionsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signed-in devices'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () =>
                context.read<SessionsBloc>().add(const SessionsRefreshed()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocConsumer<SessionsBloc, SessionsState>(
        listenWhen: (a, b) => a.endFailure != b.endFailure,
        listener: (context, state) {
          if (state.endFailure != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                  SnackBar(content: Text(state.endFailure!.message)));
          }
        },
        builder: (context, state) {
          switch (state.status) {
            case LoadStatus.initial:
            case LoadStatus.loading:
              if (state.sessions.isEmpty) return const AppLoading();
              return ListView.separated(
                padding: const EdgeInsets.all(RvmSpacing.md),
                itemCount: state.sessions.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: RvmSpacing.sm),
                itemBuilder: (context, i) => _SessionCard(
                  session: state.sessions[i],
                  ending: state.endingId == state.sessions[i].id,
                  onEnd: () => context
                      .read<SessionsBloc>()
                      .add(SessionEndRequested(state.sessions[i].id)),
                ),
              );
            case LoadStatus.failure:
              if (state.sessions.isEmpty) {
                return AppError(
                  message:
                      state.failure?.message ?? 'Could not load your sign-ins.',
                  onRetry: () => context
                      .read<SessionsBloc>()
                      .add(const SessionsRefreshed()),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(RvmSpacing.md),
                itemCount: state.sessions.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: RvmSpacing.sm),
                itemBuilder: (context, i) => _SessionCard(
                  session: state.sessions[i],
                  ending: state.endingId == state.sessions[i].id,
                  onEnd: () => context
                      .read<SessionsBloc>()
                      .add(SessionEndRequested(state.sessions[i].id)),
                ),
              );
            case LoadStatus.empty:
              return const AppEmpty(
                  icon: Icons.devices_other_outlined,
                  message: 'No kept sign-ins.');
            case LoadStatus.success:
              return ListView.separated(
                padding: const EdgeInsets.all(RvmSpacing.md),
                itemCount: state.sessions.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: RvmSpacing.sm),
                itemBuilder: (context, i) {
                  final s = state.sessions[i];
                  return _SessionCard(
                    session: s,
                    ending: state.endingId == s.id,
                    onEnd: () => context
                        .read<SessionsBloc>()
                        .add(SessionEndRequested(s.id)),
                  );
                },
              );
          }
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard(
      {required this.session, required this.ending, required this.onEnd});
  final TeamSession session;
  final bool ending;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(
            session.current ? Icons.smartphone : Icons.devices_other_outlined),
        title: Text(session.deviceLabel?.isNotEmpty == true
            ? session.deviceLabel!
            : 'Unknown device'),
        subtitle: Text([
          if (session.current) 'This phone',
          if (session.lastUsedAt != null)
            'Last used ${MaterialLocalizations.of(context).formatMediumDate(session.lastUsedAt!.toLocal())}',
          if (session.expiresAt != null)
            'Expires ${MaterialLocalizations.of(context).formatMediumDate(session.expiresAt!.toLocal())}',
        ].join(' · ')),
        trailing: session.current
            ? Chip(
                label: const Text('Current'),
                backgroundColor: RvmColors.success.withValues(alpha: 0.14),
                side: BorderSide(color: scheme.outlineVariant),
              )
            : TextButton(
                onPressed: ending ? null : onEnd,
                child: ending
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sign out'),
              ),
      ),
    );
  }
}

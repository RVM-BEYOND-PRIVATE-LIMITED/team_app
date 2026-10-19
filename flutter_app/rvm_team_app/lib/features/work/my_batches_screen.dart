import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';

/// The batches the signed-in faculty/HOD teaches (`GET /api/batches` — already
/// filtered to the caller's own batches by the server).
class MyBatchesScreen extends StatelessWidget {
  const MyBatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My batches')),
      body: BlocProvider(
        create: (_) => getIt<MyBatchesBloc>()..add(const LoadRequested()),
        child: BlocBuilder<MyBatchesBloc, LoadState<List<TeamBatch>>>(
          builder: (context, state) {
            return switch (state.status) {
              LoadStatus.loading || LoadStatus.initial => const AppLoading(),
              LoadStatus.failure => AppError(
                  message: state.failure?.message ?? 'Could not load your batches.',
                  onRetry: () => context.read<MyBatchesBloc>().add(const LoadRefreshed()),
                ),
              LoadStatus.empty => const AppEmpty(message: 'No batches are assigned to you.', icon: Icons.menu_book_outlined),
              LoadStatus.success => RefreshIndicator(
                  onRefresh: () async => context.read<MyBatchesBloc>().add(const LoadRefreshed()),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.data!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
                    itemBuilder: (context, i) => _BatchTile(batch: state.data![i]),
                  ),
                ),
            };
          },
        ),
      ),
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile({required this.batch});
  final TeamBatch batch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        onTap: () => context.push('/work/batch/${batch.id}/mark', extra: batch.name),
        title: Text(batch.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (batch.skillName != null) Text(batch.skillName!),
            Text([
              '${batch.joinedCount}/${batch.students} students',
              if (batch.schedule != null) batch.schedule!,
              if (batch.substituted) 'substituted',
            ].join(' · ')),
          ],
        ),
        isThreeLine: true,
        trailing: Chip(
          visualDensity: VisualDensity.compact,
          label: Text((batch.status ?? 'active').toUpperCase(), style: const TextStyle(fontSize: 10)),
          backgroundColor: scheme.surfaceContainerHighest,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}

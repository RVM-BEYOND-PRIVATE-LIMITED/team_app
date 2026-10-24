import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app_feedback.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import 'bloc/data_requests_bloc.dart';

/// A8: the employee's own requests to correct or delete their data, with HR's
/// answer. (Google Play's data-deletion requirement.)
class DataRequestsScreen extends StatelessWidget {
  const DataRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<DataRequestsBloc>()..add(const DataRequestsLoadRequested()),
      child: const _DataRequestsView(),
    );
  }
}

class _DataRequestsView extends StatelessWidget {
  const _DataRequestsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => context
                .read<DataRequestsBloc>()
                .add(const DataRequestsRefreshed()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('New request'),
      ),
      body: BlocConsumer<DataRequestsBloc, DataRequestsState>(
        listenWhen: (a, b) =>
            a.createdNonce != b.createdNonce ||
            a.submitFailure != b.submitFailure,
        listener: (context, state) {
          if (state.submitFailure != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                  SnackBar(content: Text(state.submitFailure!.message)));
          } else if (state.createdNonce > 0) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                  const SnackBar(content: Text('Request sent to HR.')));
          }
        },
        builder: (context, state) {
          switch (state.status) {
            case LoadStatus.initial:
            case LoadStatus.loading:
              if (state.requests.isEmpty) return const AppLoading();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: state.requests.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: RvmSpacing.sm),
                itemBuilder: (context, i) =>
                    _RequestCard(request: state.requests[i]),
              );
            case LoadStatus.failure:
              if (state.requests.isEmpty) {
                return AppError(
                  message:
                      state.failure?.message ?? 'Could not load your requests.',
                  onRetry: () => context
                      .read<DataRequestsBloc>()
                      .add(const DataRequestsRefreshed()),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: state.requests.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: RvmSpacing.sm),
                itemBuilder: (context, i) =>
                    _RequestCard(request: state.requests[i]),
              );
            case LoadStatus.empty:
              return const AppEmpty(
                icon: Icons.privacy_tip_outlined,
                message:
                    'No requests yet.\nRaise one to correct or delete your data.',
              );
            case LoadStatus.success:
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: state.requests.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: RvmSpacing.sm),
                itemBuilder: (context, i) =>
                    _RequestCard(request: state.requests[i]),
              );
          }
        },
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final bloc = context.read<DataRequestsBloc>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          BlocProvider.value(value: bloc, child: const _NewRequestSheet()),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});
  final EssDataRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(request.kindLabel,
                        style: Theme.of(context).textTheme.titleMedium)),
                _StatusChip(status: request.status),
              ],
            ),
            const SizedBox(height: RvmSpacing.sm),
            Text(request.details,
                style: Theme.of(context).textTheme.bodyMedium),
            if (request.resolutionNote != null) ...[
              const SizedBox(height: RvmSpacing.sm),
              Container(
                padding: const EdgeInsets.all(RvmSpacing.sm),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(RvmRadii.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('HR: ${request.resolutionNote}',
                        style: Theme.of(context).textTheme.bodyMedium),
                    if (request.resolvedByName != null)
                      Text('— ${request.resolvedByName}',
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      'done' => ('Done', RvmColors.success),
      'rejected' => ('Rejected', RvmColors.danger),
      _ => ('Open', scheme.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(RvmRadii.sm),
      ),
      child: Text(label,
          style:
              Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
    );
  }
}

class _NewRequestSheet extends StatefulWidget {
  const _NewRequestSheet();

  @override
  State<_NewRequestSheet> createState() => _NewRequestSheetState();
}

class _NewRequestSheetState extends State<_NewRequestSheet> {
  final _details = TextEditingController();
  String _kind = 'correct';

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final submitting =
        context.select<DataRequestsBloc, bool>((b) => b.state.submitting);
    return Padding(
      padding: EdgeInsets.only(
        left: RvmSpacing.md,
        right: RvmSpacing.md,
        top: RvmSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + RvmSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New data request',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: RvmSpacing.md),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'correct',
                  label: Text('Correct'),
                  icon: Icon(Icons.edit_outlined)),
              ButtonSegment(
                  value: 'delete',
                  label: Text('Delete'),
                  icon: Icon(Icons.delete_outline)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: RvmSpacing.md),
          TextField(
            controller: _details,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'What should HR change or delete?',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: RvmSpacing.sm),
          FilledButton(
            onPressed: submitting ? null : _submit,
            child: submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send to HR'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final details = _details.text.trim();
    if (details.length < 5) {
      showAppMessage('Please describe your request (at least 5 characters).');
      return;
    }
    context
        .read<DataRequestsBloc>()
        .add(DataRequestCreateRequested(kind: _kind, details: details));
    Navigator.of(context).pop();
  }
}

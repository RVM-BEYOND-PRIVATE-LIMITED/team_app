import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import 'bloc/hr_tools_bloc.dart';

/// HR's 1B tools: data requests (A8), mocked-location reports (B14) and
/// registered phones (B8). The backend gates each by role; the caller only
/// reaches this screen when its capabilities say HR.
class HrToolsScreen extends StatelessWidget {
  const HrToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<HrToolsBloc>()..add(const HrToolsLoadRequested()),
      child: const _HrToolsView(),
    );
  }
}

class _HrToolsView extends StatelessWidget {
  const _HrToolsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HR tools'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => context.read<HrToolsBloc>().add(const HrToolsRefreshed()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          BlocBuilder<HrToolsBloc, HrToolsState>(
            buildWhen: (a, b) => a.queue != b.queue,
            builder: (context, state) => Padding(
              padding: const EdgeInsets.all(RvmSpacing.md),
              child: SegmentedButton<HrQueue>(
                segments: const [
                  ButtonSegment(value: HrQueue.dataRequests, label: Text('Requests')),
                  ButtonSegment(value: HrQueue.reports, label: Text('Locations')),
                  ButtonSegment(value: HrQueue.devices, label: Text('Phones')),
                ],
                selected: {state.queue},
                onSelectionChanged: (s) =>
                    context.read<HrToolsBloc>().add(HrQueueSelected(s.first)),
              ),
            ),
          ),
          Expanded(
            child: BlocConsumer<HrToolsBloc, HrToolsState>(
              listenWhen: (a, b) => a.actionNonce != b.actionNonce || a.actionFailure != b.actionFailure,
              listener: (context, state) {
                if (state.actionFailure != null) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(state.actionFailure!.message)));
                } else if (state.actionNonce > 0) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(content: Text('Done.')));
                }
              },
              builder: (context, state) {
                switch (state.status) {
                  case LoadStatus.initial:
                  case LoadStatus.loading:
                    return const AppLoading();
                  case LoadStatus.failure:
                    return AppError(
                      message: state.failure?.message ?? 'Could not load this queue.',
                      onRetry: () => context.read<HrToolsBloc>().add(const HrToolsRefreshed()),
                    );
                  case LoadStatus.empty:
                    return const AppEmpty(message: 'Nothing to review here.');
                  case LoadStatus.success:
                    return _list(context, state);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, HrToolsState state) {
    switch (state.queue) {
      case HrQueue.dataRequests:
        return ListView.separated(
          padding: const EdgeInsets.all(RvmSpacing.md),
          itemCount: state.dataRequests.length,
          separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
          itemBuilder: (context, i) {
            final r = state.dataRequests[i];
            return Card(
              child: ListTile(
                title: Text('${r.kindLabel} · ${r.employee?.fullName ?? 'Unknown'}'),
                subtitle: Text(r.details),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Personal details',
                      onPressed: () => _openPersonal(context, r.employee),
                      icon: const Icon(Icons.badge_outlined),
                    ),
                    r.isOpen
                        ? const Icon(Icons.chevron_right)
                        : Text(r.status.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
                onTap: r.isOpen ? () => _resolve(context, r) : null,
              ),
            );
          },
        );
      case HrQueue.reports:
        return ListView.separated(
          padding: const EdgeInsets.all(RvmSpacing.md),
          itemCount: state.reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
          itemBuilder: (context, i) {
            final r = state.reports[i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.my_location_outlined),
                title: Text(r.employee?.fullName ?? 'Unknown'),
                subtitle: Text([
                  if (r.reportedAt != null)
                    MaterialLocalizations.of(context).formatMediumDate(r.reportedAt!.toLocal()),
                  if (r.latitude != null && r.longitude != null)
                    '${r.latitude!.toStringAsFixed(4)}, ${r.longitude!.toStringAsFixed(4)}',
                  if (r.branch?.name != null) r.branch!.name,
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openPersonal(context, r.employee),
              ),
            );
          },
        );
      case HrQueue.devices:
        return ListView.separated(
          padding: const EdgeInsets.all(RvmSpacing.md),
          itemCount: state.devices.length,
          separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
          itemBuilder: (context, i) {
            final d = state.devices[i];
            return Card(
              child: ListTile(
                leading: Icon(d.isActive ? Icons.smartphone : Icons.phonelink_erase_outlined),
                title: Text(d.employee?.fullName ?? 'Unknown'),
                subtitle: Text([
                  d.status,
                  if (d.branch?.name != null) d.branch!.name,
                  if (d.lastSeenAt != null)
                    'seen ${MaterialLocalizations.of(context).formatMediumDate(d.lastSeenAt!.toLocal())}',
                ].join(' · ')),
                trailing: d.isActive
                    ? TextButton(onPressed: () => _reset(context, d), child: const Text('Reset'))
                    : null,
                onTap: () => _openPersonal(context, d.employee),
              ),
            );
          },
        );
    }
  }

  void _openPersonal(BuildContext context, EmployeeCard? employee) {
    if (employee == null) return;
    context.push('/hr/employee/${employee.id}/personal', extra: employee.fullName);
  }

  Future<void> _resolve(BuildContext context, EssDataRequest r) async {
    final bloc = context.read<HrToolsBloc>();
    final note = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r.kindLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.details),
            const SizedBox(height: RvmSpacing.md),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Note (required to reject)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'rejected'),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'done'),
            child: const Text('Mark done'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    if (result == 'rejected' && note.text.trim().length < 3) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('A rejection needs a reason (at least 3 characters).')));
      return;
    }
    bloc.add(HrResolveDataRequestRequested(id: r.id, status: result, note: note.text.trim()));
  }

  Future<void> _reset(BuildContext context, RegisteredPhone d) async {
    final employeeId = d.employee?.id;
    if (employeeId == null) return;
    final bloc = context.read<HrToolsBloc>();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset this phone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reset the registered phone of ${d.employee?.fullName ?? 'this employee'}?'),
            const SizedBox(height: RvmSpacing.md),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (reason.text.trim().length < 3) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('A reason is required (at least 3 characters).')));
      return;
    }
    bloc.add(HrResetDevicesRequested(employeeIds: [employeeId], reason: reason.text.trim()));
  }
}

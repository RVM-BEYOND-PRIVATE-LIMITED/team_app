import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../injection.dart';
import '../../widgets/states.dart';
import 'bloc/attendance_day_bloc.dart';

/// B1: today, from the server's clock — status, timings and HR's remark — plus
/// B14: report a location the phone refused to punch with.
class AttendanceDayScreen extends StatelessWidget {
  const AttendanceDayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<AttendanceDayBloc>()..add(const AttendanceDayLoadRequested()),
      child: const _AttendanceDayView(),
    );
  }
}

class _AttendanceDayView extends StatelessWidget {
  const _AttendanceDayView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My day'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => context.read<AttendanceDayBloc>().add(const AttendanceDayRefreshed()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocConsumer<AttendanceDayBloc, AttendanceDayState>(
        listenWhen: (a, b) => a.reportedNonce != b.reportedNonce || a.reportFailure != b.reportFailure,
        listener: (context, state) {
          if (state.reportFailure != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.reportFailure!.message)));
          } else if (state.reportedNonce > 0) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Reported to HR.')));
          }
        },
        builder: (context, state) {
          switch (state.status) {
            case LoadStatus.initial:
            case LoadStatus.loading:
              return const AppLoading();
            case LoadStatus.failure:
              return AppError(
                message: state.failure?.message ?? 'Could not load today.',
                onRetry: () => context.read<AttendanceDayBloc>().add(const AttendanceDayRefreshed()),
              );
            case LoadStatus.empty:
            case LoadStatus.success:
              return _body(context, state);
          }
        },
      ),
    );
  }

  Widget _body(BuildContext context, AttendanceDayState state) {
    final day = state.day;
    final stored = day?.day;
    return ListView(
      padding: const EdgeInsets.all(RvmSpacing.md),
      children: [
        _TodayHeader(date: day?.date, serverNow: day?.serverNow),
        const SizedBox(height: RvmSpacing.md),
        Card(
          child: Column(
            children: [
              _Row(label: 'Status', value: _statusLabel(stored?.status)),
              const Divider(height: 1),
              _Row(label: 'First in', value: _time(context, stored?.firstIn)),
              const Divider(height: 1),
              _Row(label: 'Last out', value: _time(context, stored?.lastOut)),
              const Divider(height: 1),
              _Row(label: 'Worked', value: _minutes(stored?.workedMinutes)),
              if ((stored?.lateMinutes ?? 0) > 0) ...[
                const Divider(height: 1),
                _Row(label: 'Late by', value: _minutes(stored?.lateMinutes)),
              ],
              if (stored?.leaveType != null) ...[
                const Divider(height: 1),
                _Row(label: 'Leave', value: stored!.leaveType!.toUpperCase()),
              ],
            ],
          ),
        ),
        if (day?.note != null && day!.note!.isNotEmpty) ...[
          const SizedBox(height: RvmSpacing.md),
          _NoteCard(title: 'Day note', body: day.note!),
        ],
        if (day?.hrRemark != null) ...[
          const SizedBox(height: RvmSpacing.md),
          _NoteCard(title: 'HR remark', body: day!.hrRemark!.remarks),
        ],
        if (day != null && day.myRemarks.isNotEmpty) ...[
          const SizedBox(height: RvmSpacing.md),
          _NoteCard(title: 'My remarks', body: day.myRemarks.map((r) => r.remarks).join('\n')),
        ],
        const SizedBox(height: RvmSpacing.lg),
        OutlinedButton.icon(
          onPressed: state.reporting ? null : () => _report(context),
          icon: const Icon(Icons.my_location_outlined),
          label: Text(state.reporting ? 'Reporting…' : 'Report a location problem'),
        ),
        const SizedBox(height: RvmSpacing.sm),
        Text(
          'Use this when the phone refuses to punch because the location looks mocked. '
          'HR sees the report.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _report(BuildContext context) async {
    final bloc = context.read<AttendanceDayBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report a location problem'),
        content: const Text('Send HR a report that the location was refused on this phone?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Report')),
        ],
      ),
    );
    if (ok == true) bloc.add(const MockLocationReportSubmitted(provider: 'device'));
  }

  static String _statusLabel(String? status) => switch (status) {
        'present' => 'Present',
        'absent' => 'Absent',
        'half_day' => 'Half day',
        'leave' => 'On leave',
        'week_off' => 'Week off',
        'holiday' => 'Holiday',
        _ => 'Nothing recorded yet',
      };

  static String _time(BuildContext context, DateTime? dt) =>
      dt == null ? '—' : TimeOfDay.fromDateTime(dt.toLocal()).format(context);

  static String _minutes(int? m) {
    if (m == null) return '—';
    final h = m ~/ 60;
    final min = m % 60;
    return h > 0 ? '${h}h ${min}m' : '${min}m';
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({this.date, this.serverNow});
  final String? date;
  final DateTime? serverNow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RvmSpacing.md),
      decoration: BoxDecoration(
        color: RvmColors.teamSeed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(RvmRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date ?? 'Today', style: Theme.of(context).textTheme.titleLarge),
          if (serverNow != null)
            Text('Server time ${TimeOfDay.fromDateTime(serverNow!.toLocal()).format(context)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(body),
          ],
        ),
      ),
    );
  }
}

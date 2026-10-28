import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/attendance_models.dart';
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
      create: (_) =>
          getIt<AttendanceDayBloc>()..add(const AttendanceDayLoadRequested()),
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
            onPressed: () => context
                .read<AttendanceDayBloc>()
                .add(const AttendanceDayRefreshed()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocConsumer<AttendanceDayBloc, AttendanceDayState>(
        listenWhen: (a, b) =>
            a.reportedNonce != b.reportedNonce ||
            a.reportFailure != b.reportFailure,
        listener: (context, state) {
          if (state.reportFailure != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                  SnackBar(content: Text(state.reportFailure!.message)));
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
              if (state.day == null) return const AppLoading();
              return _body(context, state);
            case LoadStatus.failure:
              if (state.day == null) {
                return AppError(
                  message: state.failure?.message ?? 'Could not load today.',
                  onRetry: () => context
                      .read<AttendanceDayBloc>()
                      .add(const AttendanceDayRefreshed()),
                );
              }
              return _body(context, state);
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
          _NoteCard(
              title: 'My remarks',
              body: day.myRemarks.map((r) => r.remarks).join('\n')),
        ],
        const SizedBox(height: RvmSpacing.lg),
        Text('Attendance log', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('This month and last month',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: RvmSpacing.sm),
        if (state.logsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          if (state.logFailure != null)
            Padding(
              padding: const EdgeInsets.only(bottom: RvmSpacing.sm),
              child: Text(
                state.logFailure!.message,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _MonthLog(
            month: state.currentMonth?.month ?? _monthKey(DateTime.now()),
            attendance: state.currentMonth,
            initiallyExpanded: true,
          ),
          const SizedBox(height: RvmSpacing.sm),
          _MonthLog(
            month: state.previousMonth?.month ??
                _monthKey(
                    DateTime(DateTime.now().year, DateTime.now().month - 1)),
            attendance: state.previousMonth,
            initiallyExpanded: false,
          ),
        ],
        const SizedBox(height: RvmSpacing.lg),
        OutlinedButton.icon(
          onPressed: state.reporting ? null : () => _report(context),
          icon: const Icon(Icons.my_location_outlined),
          label: Text(
              state.reporting ? 'Reporting…' : 'Report a location problem'),
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
        content: const Text(
            'Send HR a report that the location was refused on this phone?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Report')),
        ],
      ),
    );
    if (ok == true) {
      bloc.add(const MockLocationReportSubmitted(provider: 'device'));
    }
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
            Text(
                'Server time ${TimeOfDay.fromDateTime(serverNow!.toLocal()).format(context)}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
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

String _monthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

String _monthLabel(String key) {
  final parts = key.split('-');
  if (parts.length < 2) return key;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return key;
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  return '${names[month - 1]} $year';
}

String _dayLabel(String value) {
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${d.day} ${_monthLabel('${d.year}-${d.month.toString().padLeft(2, '0')}').split(' ').first} · ${weekdays[d.weekday - 1]}';
}

String _logStatus(String status, String? leaveType) => switch (status) {
      'present' => leaveType == null ? 'Present' : leaveType.toUpperCase(),
      'absent' => 'Absent',
      'half_day' => 'Half day',
      'leave' => leaveType == null ? 'On leave' : leaveType.toUpperCase(),
      'week_off' => 'Week off',
      'holiday' => 'Holiday',
      _ => status.replaceAll('_', ' '),
    };

int _logTone(String status) {
  if (status == 'present') return 0;
  if (status == 'absent') return 1;
  if (status == 'half_day' || status == 'leave') return 2;
  return 3;
}

class _MonthLog extends StatelessWidget {
  const _MonthLog({
    required this.month,
    required this.attendance,
    required this.initiallyExpanded,
  });

  final String month;
  final MyAttendance? attendance;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final days = [...?attendance?.days]..sort((a, b) => b.day.compareTo(a.day));
    final present = days.where((d) => d.status == 'present').length;
    final absent = days.where((d) => d.status == 'absent').length;
    final leave =
        days.where((d) => d.status == 'leave' || d.status == 'half_day').length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: RvmSpacing.md),
        childrenPadding: const EdgeInsets.fromLTRB(
            RvmSpacing.md, 0, RvmSpacing.md, RvmSpacing.sm),
        title: Text(_monthLabel(month),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: days.isEmpty
            ? const Text('No attendance recorded yet')
            : Text('$present present · $absent absent · $leave leave'),
        children: [
          if (days.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No days recorded for this month.'),
            )
          else
            for (final day in days) _LogDay(day: day),
        ],
      ),
    );
  }
}

class _LogDay extends StatelessWidget {
  const _LogDay({required this.day});
  final AttendanceMonthDay day;

  @override
  Widget build(BuildContext context) {
    final color = switch (_logTone(day.status)) {
      0 => RvmColors.success,
      1 => RvmColors.danger,
      2 => RvmColors.warning,
      _ => RvmColors.muted,
    };
    final parsed = DateTime.tryParse(day.day);
    final times = [
      if (day.firstIn != null)
        'In ${TimeOfDay.fromDateTime(day.firstIn!.toLocal()).format(context)}',
      if (day.lastOut != null)
        'Out ${TimeOfDay.fromDateTime(day.lastOut!.toLocal()).format(context)}',
    ].join(' · ');
    final worked = _minutes(day.workedMinutes);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(RvmRadii.sm),
            ),
            child: Text(
              parsed == null ? '—' : '${parsed.day}',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_dayLabel(day.day),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: RvmColors.ink)),
                    ),
                    Text(_logStatus(day.status, day.leaveType),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: color)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (times.isNotEmpty) times,
                    if (worked != '—') 'Worked $worked'
                  ].join(' · '),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _minutes(int? m) {
    if (m == null) return '—';
    final h = m ~/ 60;
    final min = m % 60;
    return h > 0 ? '${h}h ${min}m' : '${min}m';
  }
}

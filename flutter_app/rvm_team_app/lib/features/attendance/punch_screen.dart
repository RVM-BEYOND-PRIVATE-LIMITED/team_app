import 'dart:async';

import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/attendance_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import 'bloc/punch_bloc.dart';

/// The geofenced self punch (Scheduler path): today, the month, this phone and
/// the rules. Punch-in is clay, punch-out Ironwood (decision 16).
class PunchScreen extends StatelessWidget {
  const PunchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<PunchBloc>()..add(const PunchLoadRequested()),
      child: const _PunchView(),
    );
  }
}

class _PunchView extends StatelessWidget {
  const _PunchView();

  @override
  Widget build(BuildContext context) {
    return TeamScaffold(
      title: 'Attendance & Punch',
      leading: const BackButton(),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () =>
              context.read<PunchBloc>().add(const PunchRefreshed()),
          icon: const Icon(Icons.refresh_rounded, size: 21),
        ),
      ],
      body: BlocConsumer<PunchBloc, PunchState>(
        listenWhen: (a, b) =>
            a.message != b.message || a.remarksNonce != b.remarksNonce,
        listener: (context, state) {
          if (state.message != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.message!)));
          }
        },
        builder: (context, state) {
          switch (state.status) {
            case LoadStatus.initial:
            case LoadStatus.loading:
              return const AppLoading(label: 'Getting your location...');
            case LoadStatus.failure:
              return AppError(
                message: state.failure?.message ?? 'Could not load attendance.',
                onRetry: () =>
                    context.read<PunchBloc>().add(const PunchRefreshed()),
              );
            case LoadStatus.empty:
            case LoadStatus.success:
              final data = state.data;
              if (data == null) {
                return const AppEmpty(message: 'Nothing to show.');
              }
              if (!data.linked) {
                return AppEmpty(
                    message: data.message ??
                        'Your login is not linked to an employee record yet.');
              }
              if (data.mustSetPassword) {
                return _SetPasswordCard(name: data.employeeName);
              }
              return _body(context, state, data);
          }
        },
      ),
    );
  }

  Widget _body(BuildContext context, PunchState state, MyAttendance data) {
    final today = data.today;
    final device = data.device;
    final isIn = today?.punchedIn ?? false;
    final monthDays = data.days;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          RvmSpacing.md, RvmSpacing.sm, RvmSpacing.md, RvmSpacing.xl),
      children: [
        _StatusCard(
          today: today,
          shift: data.shift,
          branch: data.branch,
          isIn: isIn,
          onReportDevice: () => _reportGps(context, data),
        ),
        const SizedBox(height: RvmSpacing.md),
        if (device != null) ...[
          _DeviceCard(device: device),
          const SizedBox(height: RvmSpacing.md),
        ],
        Row(
          children: [
            Expanded(
              child: _MiniAction(
                icon: Icons.edit_note_rounded,
                label: 'Add remark',
                onTap: today == null ? null : () => _remark(context, today),
              ),
            ),
            const SizedBox(width: RvmSpacing.sm),
            Expanded(
              child: _MiniAction(
                icon: Icons.my_location_rounded,
                label: 'Report GPS Issue',
                onTap: () => _reportGps(context, data),
              ),
            ),
          ],
        ),
        const SizedBox(height: RvmSpacing.lg),
        _MonthOverview(days: monthDays),
        const SizedBox(height: RvmSpacing.md),
        _DayList(days: monthDays),
        if (today != null && today.punches.isNotEmpty) ...[
          const SizedBox(height: RvmSpacing.lg),
          const TeamSectionHeader(title: 'Today\'s punches'),
          const SizedBox(height: RvmSpacing.sm),
          TeamCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < today.punches.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: TeamIconBadge(
                      icon: today.punches[i].kind == 'in'
                          ? Icons.login_rounded
                          : Icons.logout_rounded,
                      size: 32,
                      iconSize: 15,
                      color: today.punches[i].kind == 'in'
                          ? RvmColors.success
                          : RvmColors.clay,
                      background: today.punches[i].kind == 'in'
                          ? RvmColors.successSoft
                          : RvmColors.claySoft,
                    ),
                    title: Text(
                        today.punches[i].kind == 'in'
                            ? 'Punched in'
                            : 'Punched out',
                        style: Theme.of(context).textTheme.bodyMedium),
                    trailing: Text(
                      today.punches[i].at == null
                          ? '—'
                          : TimeOfDay.fromDateTime(
                                  today.punches[i].at!.toLocal())
                              .format(context),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: RvmSpacing.lg),
        Center(
          child: Text(
            'Attendance is verified against the office geofence.\nTimes shown are from the server clock.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: 10, color: RvmColors.subtle),
          ),
        ),
        if (state.punching) ...[
          const SizedBox(height: RvmSpacing.md),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  Future<void> _remark(BuildContext context, PunchToday today) async {
    final existing = context.read<PunchBloc>().state.data?.myRemarks ??
        const <AttendanceRemark>[];
    final mine = existing.where((r) => r.day == today.day);
    final controller =
        TextEditingController(text: mine.isEmpty ? '' : mine.first.remarks);
    final bloc = context.read<PunchBloc>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remark for today'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'The bus was late...',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) bloc.add(PunchRemarkRequested(controller.text.trim()));
  }

  Future<void> _reportGps(BuildContext context, MyAttendance data) async {
    final bloc = context.read<PunchBloc>();
    final controller = TextEditingController();
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _GpsIssueSheet(
        branch: data.branch?.name,
        device: data.device,
        controller: controller,
      ),
    );
    if (submitted == true) {
      final text = controller.text.trim();
      bloc.add(PunchRemarkRequested(
        text.isEmpty ? 'GPS issue reported from the app.' : 'GPS issue: $text',
      ));
    }
  }
}

// ── status ────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.today,
    this.shift,
    this.branch,
    required this.isIn,
    required this.onReportDevice,
  });

  final PunchToday? today;
  final AttendanceShift? shift;
  final AttendanceBranch? branch;
  final bool isIn;
  final VoidCallback onReportDevice;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shiftText = (shift?.start != null && shift?.end != null)
        ? 'Shift: ${shift!.start} – ${shift!.end}'
        : (shift?.name ?? 'Shift not set');
    final branchText = branch?.name != null ? ' · ${branch!.name}' : '';
    final canPunch = context.watch<PunchBloc>().state;
    final device = canPunch.data?.device;
    final allowed =
        device == null || device.thisPhone == 'own' || device.canRegister;
    final done = today?.done ?? false;
    final blockReason = _deviceBlockReason(device);
    final phoneVerified = device?.thisPhone == 'own';
    final phoneWillRegister = device?.canRegister ?? false;

    return TeamCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TeamPill(
                label: isIn
                    ? 'Clocked In'
                    : (done ? 'Clocked Out' : 'Awaiting Clock-In'),
                tone: isIn ? TeamPillTone.success : TeamPillTone.warning,
                dot: true,
              ),
              const Spacer(),
              const _LiveClock(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
              isIn
                  ? 'Punched in'
                  : (done ? 'Done for today' : 'Not punched in'),
              style: text.headlineMedium
                  ?.copyWith(fontSize: 24, letterSpacing: -0.5)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: RvmColors.cream,
              borderRadius: BorderRadius.circular(RvmRadii.sm),
              border: Border.all(color: RvmColors.sand),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 14, color: RvmColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('$shiftText$branchText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall
                          ?.copyWith(fontSize: 11.5, color: RvmColors.muted)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TeamPrimaryButton(
            label: done
                ? 'Punched out for today'
                : allowed
                    ? (isIn ? 'Punch Out Now' : 'Punch In Now')
                    : 'Punch unavailable',
            icon: done
                ? Icons.check_rounded
                : (allowed ? Icons.add_rounded : Icons.info_outline_rounded),
            color: isIn
                ? RvmColors.ironwood
                : (allowed ? RvmColors.clay : RvmColors.muted),
            busy: canPunch.punching,
            onPressed: (canPunch.punching || done)
                ? null
                : () {
                    if (!allowed) {
                      _showDeviceBlock(context, blockReason);
                      return;
                    }
                    _punch(context, isIn ? 'out' : 'in');
                  },
          ),
          if (!allowed && blockReason != null) ...[
            const SizedBox(height: 10),
            TeamNotice(
              icon: Icons.phonelink_erase_rounded,
              tone: TeamPillTone.danger,
              text: blockReason,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onReportDevice,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Report this phone to HR',
                    style: TextStyle(fontSize: 10.5)),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStatus(
                icon: phoneVerified || phoneWillRegister
                    ? Icons.verified_rounded
                    : Icons.error_outline_rounded,
                label: phoneVerified
                    ? 'Verified Phone'
                    : (phoneWillRegister
                        ? 'Phone will be registered'
                        : 'Phone not verified'),
                color: phoneVerified || phoneWillRegister
                    ? RvmColors.success
                    : RvmColors.danger,
              ),
              const SizedBox(width: 14),
              _MiniStatus(
                icon: Icons.location_on_rounded,
                label: branch?.configured == true
                    ? 'Office geofence active'
                    : 'Geofence not set up',
                color: branch?.configured == true
                    ? RvmColors.success
                    : RvmColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _punch(BuildContext context, String kind) {
    context.read<PunchBloc>().add(PunchRequested(kind));
  }

  void _showDeviceBlock(BuildContext context, String? reason) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.phone_android_rounded, color: RvmColors.danger),
        title: const Text('Punch unavailable on this phone'),
        content: Text(reason ??
            'This phone is not the one registered for your attendance. Ask HR to reset it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onReportDevice();
            },
            child: const Text('Report to HR'),
          ),
        ],
      ),
    );
  }
}

/// The live server-clock display. It owns its timer so only this text rebuilds
/// every second; the punch button and the rest of the card stay stable, so a
/// tap can never be lost to a rebuild.
class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clock =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(clock,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
        Text('IST · SERVER SYNCED',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 8,
                letterSpacing: 0.6,
                color: RvmColors.subtle,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

String? _deviceBlockReason(AttendanceDevice? device) {
  if (device == null || device.thisPhone == 'own') return null;
  return switch (device.thisPhone) {
    'other' =>
      'This phone is registered to another employee. Each person punches from their own phone.',
    'revoked' =>
      'HR has reset this phone. Punch from your new phone, or ask HR to reset it again.',
    _ => device.canRegister
        ? null
        : 'Your attendance is registered to a different phone. Ask HR to reset your phone if you have changed it.',
  };
}

class _MiniStatus extends StatelessWidget {
  const _MiniStatus(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: RvmColors.muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    )),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});
  final AttendanceDevice device;

  @override
  Widget build(BuildContext context) {
    final registered = device.thisPhone == 'own';
    final text = registered
        ? 'Registered to primary profile. If switching phones, kindly submit a verification request to HR.'
        : 'This phone is not the one registered to you. Ask HR to reset it before you punch.';
    return TeamNotice(
      icon: Icons.phone_android_rounded,
      tone: registered ? TeamPillTone.clay : TeamPillTone.danger,
      title: 'Device Security Status',
      text: text,
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RvmColors.white,
      borderRadius: BorderRadius.circular(RvmRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RvmRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RvmRadii.md),
            border: Border.all(color: RvmColors.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: RvmColors.clay),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontSize: 11,
                          color: RvmColors.ink,
                          fontWeight: FontWeight.w600,
                        )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── month overview ────────────────────────────────────────────────────────

class _MonthOverview extends StatelessWidget {
  const _MonthOverview({required this.days});
  final List<AttendanceMonthDay> days;

  @override
  Widget build(BuildContext context) {
    var present = 0, half = 0, absent = 0, off = 0;
    for (final d in days) {
      switch (d.status) {
        case 'present':
          present++;
        case 'half_day':
          half++;
        case 'absent':
          absent++;
        case 'week_off' || 'weekly_off' || 'holiday' || 'off':
          off++;
        default:
          break;
      }
    }
    final now = DateTime.now();
    const months = [
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
      'December',
    ];
    final title = '${months[now.month - 1]} ${now.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontSize: 16)),
                  Text('Monthly Attendance Overview',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontSize: 10)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _showMonthLog(context, days),
              child: Row(
                children: [
                  Text('View full log',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontSize: 10.5,
                            color: RvmColors.clay,
                            fontWeight: FontWeight.w600,
                          )),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 12, color: RvmColors.clay),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TeamMetricTile(
                  value: '$present',
                  label: 'Present',
                  tone: RvmColors.success,
                  soft: RvmColors.successSoft),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TeamMetricTile(
                  value: '$half',
                  label: 'Half-day',
                  tone: RvmColors.warning,
                  soft: RvmColors.warningSoft),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TeamMetricTile(
                  value: '$absent',
                  label: 'Absent',
                  tone: RvmColors.danger,
                  soft: RvmColors.dangerSoft),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TeamMetricTile(
                  value: '$off',
                  label: 'Off-days',
                  tone: RvmColors.muted,
                  soft: RvmColors.cream),
            ),
          ],
        ),
      ],
    );
  }

  void _showMonthLog(BuildContext context, List<AttendanceMonthDay> days) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            TeamSheetHeader(
              title: 'Monthly log',
              icon: Icons.calendar_month_rounded,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 12),
            TeamCard(
                padding: EdgeInsets.zero,
                child:
                    Column(children: [for (final d in days) _DayRow(day: d)])),
          ],
        ),
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.days});
  final List<AttendanceMonthDay> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return TeamCard(
        child: Text('No attendance recorded this month yet.',
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return TeamCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [for (final d in days.reversed.take(12)) _DayRow(day: d)],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});
  final AttendanceMonthDay day;

  @override
  Widget build(BuildContext context) {
    final (color, soft) = switch (day.status) {
      'present' => (RvmColors.success, RvmColors.successSoft),
      'absent' => (RvmColors.danger, RvmColors.dangerSoft),
      'half_day' => (RvmColors.warning, RvmColors.warningSoft),
      'holiday' => (RvmColors.info, RvmColors.infoSoft),
      _ => (RvmColors.subtle, RvmColors.cream),
    };
    final label = _statusLabel(day.status);
    final inTime = day.firstIn == null
        ? '—'
        : TimeOfDay.fromDateTime(day.firstIn!.toLocal()).format(context);
    final outTime = day.lastOut == null
        ? '—'
        : TimeOfDay.fromDateTime(day.lastOut!.toLocal()).format(context);
    final worked = day.workedMinutes == null
        ? null
        : '${day.workedMinutes! ~/ 60}h ${(day.workedMinutes! % 60).toString().padLeft(2, '0')}m';
    final note = day.leaveType ??
        (day.lateExcused
            ? 'Late excused'
            : (day.lateMinutes != null ? 'Late ${day.lateMinutes}m' : null));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_prettyDay(day.day),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: soft,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(label,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: day.status == 'present'
                                        ? RvmColors.success
                                        : color,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                  )),
                    ),
                    if (worked != null) ...[
                      const SizedBox(width: 6),
                      Text(worked,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  fontSize: 9.5, color: RvmColors.muted)),
                    ] else if (note != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    fontSize: 9.5, color: RvmColors.muted)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$inTime  –  $outTime',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: RvmColors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              const SizedBox(height: 2),
              Text(
                day.status == 'present'
                    ? 'On Time'
                    : (day.status == 'half_day' ? 'Regular shift' : ''),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 8.5,
                      color: day.status == 'present'
                          ? RvmColors.success
                          : RvmColors.subtle,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
      'present' => 'Present',
      'absent' => 'Unplanned Absent',
      'half_day' => 'Half Day',
      'week_off' || 'weekly_off' => 'Weekly Off',
      'holiday' => 'Holiday',
      'leave' => 'On Leave',
      _ => status
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' '),
    };

String _prettyDay(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
}

// ── device warning / password ────────────────────────────────────────────

class _SetPasswordCard extends StatefulWidget {
  const _SetPasswordCard({this.name});
  final String? name;

  @override
  State<_SetPasswordCard> createState() => _SetPasswordCardState();
}

class _SetPasswordCardState extends State<_SetPasswordCard> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.select<PunchBloc, bool>((b) => b.state.punching);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(RvmSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TeamIconBadge(
                    icon: Icons.lock_reset_rounded,
                    size: 56,
                    iconSize: 26,
                    radius: 18),
                const SizedBox(height: RvmSpacing.md),
                Text('Choose your attendance password',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: RvmSpacing.xs),
                Text(
                  widget.name == null
                      ? 'You signed in with the password HR gave. Set your own before you can punch.'
                      : 'Hi ${widget.name}. Set your own attendance password before you can punch.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: RvmColors.muted),
                ),
                const SizedBox(height: RvmSpacing.lg),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'New attendance password',
                    helperText: 'At least 8 characters.',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 8)
                      ? 'At least 8 characters'
                      : null,
                ),
                const SizedBox(height: RvmSpacing.lg),
                TeamPrimaryButton(
                  label: 'Set password',
                  busy: busy,
                  onPressed: busy ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<PunchBloc>().add(PunchSetPasswordRequested(_password.text));
  }
}

// ── GPS report sheet ──────────────────────────────────────────────────────

class _GpsIssueSheet extends StatefulWidget {
  const _GpsIssueSheet({required this.controller, this.branch, this.device});
  final TextEditingController controller;
  final String? branch;
  final AttendanceDevice? device;

  @override
  State<_GpsIssueSheet> createState() => _GpsIssueSheetState();
}

class _GpsIssueSheetState extends State<_GpsIssueSheet> {
  int _reason = 0;
  bool _registerDevice = false;

  static const _reasons = [
    'GPS Mismatch / Drift detected',
    'Wrong location shown',
    'Network timeout during punch',
    'Accuracy too low',
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 2),
            const Center(
                child: TeamIconBadge(
                    icon: Icons.gps_fixed_rounded,
                    size: 46,
                    iconSize: 22,
                    radius: 14)),
            const SizedBox(height: 8),
            Text('Report GPS or Device Issue',
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(fontSize: 17)),
            const SizedBox(height: 4),
            Text(
              'Unable to punch in due to GPS drift or unregistered device? Submit a note to HR for attendance regularization.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(fontSize: 10.5),
            ),
            const SizedBox(height: 14),
            _sheetInfo(
              context,
              icon: Icons.my_location_rounded,
              title: 'DETECTED LOCATION',
              value: widget.branch ?? 'Location unavailable',
              color: RvmColors.success,
            ),
            const SizedBox(height: 8),
            _sheetInfo(
              context,
              icon: Icons.phone_android_rounded,
              title: 'HARDWARE PROFILE',
              value: widget.device == null
                  ? 'Primary phone'
                  : (widget.device!.thisPhone == 'own'
                      ? 'Registered primary phone'
                      : 'Unregistered phone'),
              color: RvmColors.clay,
            ),
            const SizedBox(height: 14),
            Text('ISSUE REASON',
                style: text.labelSmall?.copyWith(
                    fontSize: 9.5, letterSpacing: 0.7, color: RvmColors.muted)),
            const SizedBox(height: 8),
            for (var i = 0; i < _reasons.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _reason = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          _reason == i ? RvmColors.claySoft : RvmColors.white,
                      borderRadius: BorderRadius.circular(RvmRadii.sm),
                      border: Border.all(
                          color: _reason == i
                              ? RvmColors.clay.withValues(alpha: 0.35)
                              : RvmColors.line),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _reason == i
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 15,
                          color:
                              _reason == i ? RvmColors.clay : RvmColors.subtle,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_reasons[i],
                              style: text.bodySmall?.copyWith(
                                fontSize: 11.5,
                                fontWeight: _reason == i
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: _reason == i
                                    ? RvmColors.ink
                                    : RvmColors.muted,
                              )),
                        ),
                        if (i == 0)
                          const TeamPill(
                              label: 'Common',
                              tone: TeamPillTone.orange,
                              dense: true),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text('ADD REMARK FOR HR',
                style: text.labelSmall?.copyWith(
                    fontSize: 9.5, letterSpacing: 0.7, color: RvmColors.muted)),
            const SizedBox(height: 6),
            TextField(
              controller: widget.controller,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText:
                    'e.g. In basement office floor B2, GPS precision low.',
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _registerDevice,
              onChanged: (v) => setState(() => _registerDevice = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('Register this phone with HR',
                  style: text.bodySmall
                      ?.copyWith(fontSize: 11, color: RvmColors.ink)),
            ),
            const SizedBox(height: 6),
            TeamPrimaryButton(
              label: 'Submit Report to HR',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: RvmColors.muted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetInfo(BuildContext context,
      {required IconData icon,
      required String title,
      required String value,
      required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: RvmColors.cream,
        borderRadius: BorderRadius.circular(RvmRadii.sm),
        border: Border.all(color: RvmColors.sand),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 7.5,
                        letterSpacing: 0.6,
                        color: RvmColors.subtle)),
                const SizedBox(height: 1),
                Text(value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: RvmColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

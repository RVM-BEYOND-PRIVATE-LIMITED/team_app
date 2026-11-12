import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/leave_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/team_kit.dart';
import 'bloc/requests_bloc.dart';

/// Opens the raise-request form as a bottom sheet, keeping the requests bloc.
Future<void> showRaiseRequestSheet(BuildContext context) {
  final bloc = context.read<RequestsBloc>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(value: bloc, child: const _RaiseSheet()),
  );
}

class _RaiseSheet extends StatefulWidget {
  const _RaiseSheet();

  @override
  State<_RaiseSheet> createState() => _RaiseSheetState();
}

class _RaiseSheetState extends State<_RaiseSheet> {
  String _family = 'attendance';
  String _type = 'on_duty';
  DateTime _day = DateTime.now();
  DateTime _endDay = DateTime.now();
  bool _multiDay = false;
  String _portion = 'full';
  final _reason = TextEditingController();
  final _place = TextEditingController();
  final _fixIn = TextEditingController();
  final _fixOut = TextEditingController();
  String? _error;

  /// Leave (#43): "I have spoken to my approver about this leave".
  bool _spoke = false;

  /// "Goes to X, then Y" for the chosen dates, from `/leave/route`.
  LeaveRoute? _route;
  bool _routeLoading = false;
  int _routeSeq = 0;

  @override
  void dispose() {
    _reason.dispose();
    _place.dispose();
    _fixIn.dispose();
    _fixOut.dispose();
    super.dispose();
  }

  void _setFamily(String family) {
    setState(() {
      _family = family;
      _type = family == 'leave' ? 'cl' : 'on_duty';
      _multiDay = false;
      _portion = 'full';
      _error = null;
      _keepDayInWindow();
      _route = _leave?.myRoute;
    });
    _refreshRoute();
  }

  /// The Scheduler's leave rules, loaded with the requests (#43); null when
  /// that half could not load.
  LeaveOverview? get _leave => context.read<RequestsBloc>().state.leave;

  /// The first day a person may apply for themselves: today + 3 (IST). A
  /// leave starting sooner goes through the approver and HR instead.
  DateTime? get _earliestLeaveDay {
    final raw = _leave?.earliestSelfDay;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> _refreshRoute() async {
    if (_family != 'leave' || _leave == null) return;
    final seq = ++_routeSeq;
    setState(() => _routeLoading = true);
    try {
      final preview = await getIt<LeaveRepository>().route(
        day: _dayIso,
        endDay: _multiDay ? _endDayIso : null,
        portion: _portion,
      );
      if (!mounted || seq != _routeSeq) return;
      setState(() {
        _route = preview.route;
        _routeLoading = false;
      });
    } on Failure {
      if (!mounted || seq != _routeSeq) return;
      // The preview is a help, not a gate: keep the person's usual route.
      setState(() {
        _route = _leave?.myRoute;
        _routeLoading = false;
      });
    }
  }

  void _setType(String type) {
    setState(() {
      _type = type;
      _error = null;
      _keepDayInWindow();
    });
  }

  /// A fix describes a day that has happened, so the server refuses a future
  /// one. Keeping the picker inside the same window
  /// avoids a needless 400; on duty and leave may still be filed ahead.
  bool get _mayBeAhead => _family == 'leave' || _type == 'on_duty';

  /// The server's reach-back window: this month, or last month up to the
  /// payroll cut-off (the 5th). A day before it is a 400/409 the picker can
  /// simply not offer.
  DateTime get _firstSelectable {
    final earliest = _earliestLeaveDay;
    if (_family == 'leave' && earliest != null) return earliest;
    final now = DateTime.now();
    return DateTime(now.year, now.month - (now.day <= 5 ? 1 : 0), 1);
  }

  /// Leave is planned ahead; 180 days is the picker's horizon.
  DateTime get _lastSelectable => _family == 'leave'
      ? _firstSelectable.add(const Duration(days: 180))
      : _mayBeAhead
          ? DateTime.now().add(const Duration(days: 62))
          : DateTime.now();

  void _keepDayInWindow() {
    final today = DateTime.now();
    if (!_mayBeAhead && _day.isAfter(today)) _day = today;
    if (_day.isBefore(_firstSelectable)) {
      _day = _family == 'leave' ? _firstSelectable : today;
    }
    if (_endDay.isBefore(_day)) _endDay = _day;
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _dayIso => _iso(_day);
  String get _endDayIso => _iso(_multiDay ? _endDay : _day);

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: _firstSelectable,
      lastDate: _lastSelectable,
      helpText: _multiDay ? 'Pick the first day' : 'Pick the day',
    );
    if (picked != null) {
      setState(() {
        _day = picked;
        if (_endDay.isBefore(_day)) _endDay = _day;
        _error = null;
      });
      _refreshRoute();
    }
  }

  Future<void> _pickEndDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDay.isBefore(_day) ? _day : _endDay,
      firstDate: _day,
      // The Scheduler takes a range of up to 62 days.
      lastDate: _family == 'leave'
          ? _day.add(const Duration(days: 61))
          : now.add(const Duration(days: 62)),
      helpText: 'Pick the last day',
    );
    if (picked != null) {
      setState(() {
        _endDay = picked;
        _error = null;
      });
      _refreshRoute();
    }
  }

  TimeOfDay? _timeOfDay(String raw) {
    final value = _normalizeTime(raw);
    if (value == null) return null;
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(
    TextEditingController controller,
    String helpText, {
    required TimeOfDay fallback,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDay(controller.text) ?? fallback,
      helpText: helpText,
    );
    if (picked == null) return;
    setState(() {
      controller.text = _formatTime(picked);
      _error = null;
    });
  }

  /// '9:5' / '9:05' / '09:05' -> '09:05'; blank or unreadable -> null.
  String? _normalizeTime(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(value);
    final hour = match == null ? null : int.tryParse(match.group(1)!);
    final minute = match == null ? null : int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  bool _blankOrValidTime(String raw) =>
      raw.trim().isEmpty || _normalizeTime(raw) != null;

  void _submit() {
    _error = null;
    final reason = _reason.text.trim();
    if (reason.length < 5) {
      _showError('Please give a reason (at least 5 characters).');
      return;
    }
    if (_family == 'attendance' &&
        _type == 'on_duty' &&
        _place.text.trim().isEmpty) {
      _showError('On duty needs a place.');
      return;
    }
    final fixInRaw = _fixIn.text.trim();
    final fixOutRaw = _fixOut.text.trim();
    if (_family == 'attendance' && _type == 'fix_a_day') {
      if (fixInRaw.isEmpty && fixOutRaw.isEmpty) {
        _showError('A fix a day needs a time in or out.');
        return;
      }
      if (!_blankOrValidTime(fixInRaw) || !_blankOrValidTime(fixOutRaw)) {
        _showError('Use HH:MM for the times, for example 09:30.');
        return;
      }
      final inTime = _normalizeTime(fixInRaw);
      final outTime = _normalizeTime(fixOutRaw);
      if (inTime != null && outTime != null && outTime.compareTo(inTime) <= 0) {
        _showError('Punch out must be after punch in.');
        return;
      }
    }
    if (_family == 'leave') {
      final leave = _leave;
      if (leave == null) {
        _showError(_leaveUnavailable);
        return;
      }
      final earliest = _earliestLeaveDay;
      if (earliest != null && _day.isBefore(earliest)) {
        _showError(leave.shortNoticeMessage ??
            'Leave starting within 2 days: speak to your approver. They will inform HR.');
        return;
      }
      if (!_spoke) {
        _showError(
            'Tick "I have spoken to my approver about this leave" first.');
        return;
      }
      if (_multiDay && _endDay.isBefore(_day)) {
        _showError('The last day cannot be before the first day.');
        return;
      }
      if (_portion != 'full' && _multiDay) {
        _showError('A half day is a single day. Choose one day, or a full day.');
        return;
      }
    }
    final bloc = context.read<RequestsBloc>();
    // The balances on screen are for the CURRENT month. The date picker also
    // allows next month, so only apply this local check when the chosen day is
    // in that same month; otherwise the server decides with its own month data.
    // Leave has no local check: the Scheduler uses CL where the person has it
    // and writes the rest as LWP (#43), so CL running out never refuses it.
    final balance = _family == 'leave' ? null : _balanceFor(bloc.state.balances);
    final remaining = balance?.remaining ??
        (balance?.allowed == null
            ? null
            : balance!.allowed! - balance.used - balance.pending);
    if (balance != null && remaining != null) {
      if (_family == 'leave' && !_multiDay) {
        // A half day costs 0.5, a full day 1. A range is left to the server,
        // which knows the working days after skipping weekly offs and holidays.
        final needed = _portion == 'full' ? 1 : 0.5;
        if (remaining < needed) {
          _showError(_limitMessage(balance));
          return;
        }
      } else if (remaining <= 0) {
        _showError(_limitMessage(balance));
        return;
      }
    }
    // Stop the known duplicate before the server answers 409. The list may be
    // stale by a few seconds, so the bloc still handles a server refusal.
    final duplicate = bloc.state.requests.any((r) {
      if (!r.isPending || r.family != _family) return false;
      // The Scheduler refuses an overlap across CL and LWP alike (#43).
      if (_family == 'leave') {
        if (r.type == 'wfh') return false;
      } else if (r.type != _type) {
        return false;
      }
      if (_family != 'leave') return r.day == _dayIso;
      final otherEnd = r.endDay ?? r.day;
      return r.day.compareTo(_endDayIso) <= 0 && otherEnd.compareTo(_dayIso) >= 0;
    });
    if (duplicate) {
      _showError(
          'You already have a pending request overlapping those dates. Wait for it to be decided.');
      return;
    }
    bloc.add(RequestCreateRequested(
      family: _family,
      type: _type,
      day: _dayIso,
      endDay: _family == 'leave' ? _endDayIso : null,
      portion: _family == 'leave' ? _portion : 'full',
      reason: reason,
      place: _type == 'on_duty' ? _place.text.trim() : null,
      fixIn: _type == 'fix_a_day' ? _normalizeTime(fixInRaw) : null,
      fixOut: _type == 'fix_a_day' ? _normalizeTime(fixOutRaw) : null,
      spokeToApprover: _family == 'leave' && _spoke,
    ));
    // Do not pop here: the listeners below pop on success and keep the sheet
    // open on a refusal, with the message inside the sheet where it is visible.
  }

  LeaveBalanceType? _balanceFor(LeaveBalances? balances) {
    if (balances == null) return null;
    // The form may be filed for next month; the shown balances only describe
    // the current month, so they cannot decide that request.
    if (balances.month != _dayIso.substring(0, 7)) return null;
    for (final type in balances.types) {
      if (type.type == _type) return type;
    }
    return null;
  }

  String get _leaveUnavailable {
    final reason = context.read<RequestsBloc>().state.leaveFailure?.message;
    return reason == null || reason.isEmpty
        ? 'Leave cannot be applied for right now. Try again shortly.'
        : 'Leave cannot be applied for right now: $reason';
  }

  String _formatDays(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  String _limitMessage(LeaveBalanceType balance) {
    final detail =
        '(${_formatDays(balance.used)} used, ${_formatDays(balance.pending)} pending)';
    return switch (_type) {
      'fix_a_day' => "You have reached this month's Fix a Day limit $detail.",
      _ => "You have reached this month's limit for this request $detail.",
    };
  }

  void _showError(String message) {
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final types = _family == 'leave'
        // CL is automatic (#43): "Leave" uses CL where the person has it this
        // month and writes the rest as LWP; "Without pay" is all LWP.
        ? const [('cl', 'Leave (CL if available, else LWP)'), ('lwp', 'Without pay')]
        // Excuse-late and short leave were switched off on 12 Nov 2026 (#44).
        : const [('on_duty', 'On duty'), ('fix_a_day', 'Fix a day')];
    final submitting =
        context.select<RequestsBloc, bool>((b) => b.state.submitting);
    final leave =
        context.select<RequestsBloc, LeaveOverview?>((b) => b.state.leave);
    return MultiBlocListener(
      listeners: [
        BlocListener<RequestsBloc, RequestsState>(
          listenWhen: (a, b) => a.submitFailure != b.submitFailure,
          listener: (context, state) {
            final failure = state.submitFailure;
            if (failure != null) _showError(failure.message);
          },
        ),
        BlocListener<RequestsBloc, RequestsState>(
          listenWhen: (a, b) => a.createdNonce != b.createdNonce,
          listener: (context, state) {
            if (state.createdNonce == 0) return;
            Navigator.of(context).pop();
          },
        ),
      ],
      child: Padding(
        padding: EdgeInsets.only(
          left: RvmSpacing.md,
          right: RvmSpacing.md,
          top: RvmSpacing.sm,
          bottom: MediaQuery.of(context).viewInsets.bottom + RvmSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New request',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: RvmSpacing.md),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'attendance',
                      label: Text('Attendance'),
                      icon: Icon(Icons.schedule)),
                  ButtonSegment(
                      value: 'leave',
                      label: Text('Leave'),
                      icon: Icon(Icons.beach_access_outlined)),
                ],
                selected: {_family},
                onSelectionChanged: (s) => _setFamily(s.first),
              ),
              const SizedBox(height: RvmSpacing.md),
              DropdownButtonFormField<String>(
                // Rebuild when the family's type list changes; without this the
                // field keeps the previous family's value and the form can send a
                // type its own family does not take.
                key: ValueKey('type-$_family'),
                initialValue: _type,
                // The leave labels are long (#43); fit any phone width.
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Type', border: OutlineInputBorder()),
                items: [
                  for (final t in types)
                    DropdownMenuItem(
                        value: t.$1,
                        child: Text(t.$2,
                            maxLines: 1, overflow: TextOverflow.ellipsis))
                ],
                onChanged: (v) {
                  if (v != null) _setType(v);
                },
              ),
              const SizedBox(height: RvmSpacing.md),
              OutlinedButton.icon(
                onPressed: _pickDay,
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(
                    '${_multiDay ? 'From' : 'Date'}: ${MaterialLocalizations.of(context).formatMediumDate(_day)}'),
              ),
              if (_family == 'leave') ...[
                const SizedBox(height: 6),
                // Talk first (#43): leave starting within 2 days is not applied
                // for here; the approver tells HR, who records it.
                Text(
                  leave?.shortNoticeMessage ??
                      'Leave starting within 2 days: speak to your approver. They will inform HR.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: RvmColors.subtle,
                      ),
                ),
                const SizedBox(height: RvmSpacing.sm),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        label: Text('Single day'),
                        icon: Icon(Icons.today_rounded)),
                    ButtonSegment(
                        value: true,
                        label: Text('Multiple days'),
                        icon: Icon(Icons.date_range_rounded)),
                  ],
                  selected: {_multiDay},
                  onSelectionChanged: (s) {
                    setState(() {
                      _multiDay = s.first;
                      _endDay = _day;
                      _error = null;
                    });
                    _refreshRoute();
                  },
                ),
                if (_multiDay) ...[
                  const SizedBox(height: RvmSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _pickEndDay,
                    icon: const Icon(Icons.event_available_rounded),
                    label: Text(
                        'To: ${MaterialLocalizations.of(context).formatMediumDate(_endDay)}'),
                  ),
                ],
                const SizedBox(height: RvmSpacing.sm),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'full', label: Text('Full day')),
                    ButtonSegment(
                        value: 'first_half', label: Text('First half')),
                    ButtonSegment(
                        value: 'second_half', label: Text('Second half')),
                  ],
                  selected: {_portion},
                  onSelectionChanged: (s) {
                    setState(() {
                      _portion = s.first;
                      if (_portion != 'full') _multiDay = false;
                      _error = null;
                    });
                    _refreshRoute();
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _multiDay
                      ? 'Working days are counted when you send. Sundays, weekly offs and holidays are skipped.'
                      : _type == 'cl'
                          ? 'Uses your casual leave for the month if you have it; the rest is written as leave without pay.'
                          : 'Written as leave without pay. A half day counts as 0.5.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: RvmColors.subtle,
                      ),
                ),
                if (leave == null) ...[
                  const SizedBox(height: RvmSpacing.sm),
                  TeamNotice(
                    icon: Icons.cloud_off_rounded,
                    tone: TeamPillTone.danger,
                    text: _leaveUnavailable,
                  ),
                ] else ...[
                  const SizedBox(height: RvmSpacing.sm),
                  _RoutePreview(route: _route, loading: _routeLoading),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    value: _spoke,
                    onChanged: (v) => setState(() {
                      _spoke = v ?? false;
                      _error = null;
                    }),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                        'I have spoken to my approver about this leave.'),
                  ),
                ],
              ],
              const SizedBox(height: RvmSpacing.md),
              if (_type == 'on_duty')
                TextField(
                  controller: _place,
                  maxLength: 120,
                  decoration: const InputDecoration(
                      labelText: 'Place',
                      counterText: '',
                      border: OutlineInputBorder()),
                ),
              if (_type == 'fix_a_day') ...[
                const SizedBox(height: RvmSpacing.sm),
                Row(children: [
                  Expanded(
                    child: _TimeField(
                      controller: _fixIn,
                      label: 'Punch in',
                      onTap: () => _pickTime(
                        _fixIn,
                        'When did you punch in?',
                        fallback: const TimeOfDay(hour: 9, minute: 0),
                      ),
                    ),
                  ),
                  const SizedBox(width: RvmSpacing.sm),
                  Expanded(
                    child: _TimeField(
                      controller: _fixOut,
                      label: 'Punch out',
                      onTap: () => _pickTime(
                        _fixOut,
                        'When did you punch out?',
                        fallback: const TimeOfDay(hour: 18, minute: 0),
                      ),
                    ),
                  ),
                ]),
              ],
              if (_type == 'on_duty' || _type == 'fix_a_day')
                const SizedBox(height: RvmSpacing.md),
              TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                    labelText: 'Reason',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder()),
              ),
              if (_error != null) ...[
                const SizedBox(height: RvmSpacing.sm),
                TeamNotice(
                  icon: Icons.error_outline_rounded,
                  tone: TeamPillTone.danger,
                  text: _error!,
                ),
              ],
              const SizedBox(height: RvmSpacing.sm),
              FilledButton(
                onPressed: submitting ? null : _submit,
                child: submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send to approver'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A read-only field that opens the system time picker. The value is still
/// normalised and validated by the form before it is sent.
/// "Goes to Shallu, then Bhupender" for the chosen dates (#43).
class _RoutePreview extends StatelessWidget {
  const _RoutePreview({required this.route, required this.loading});
  final LeaveRoute? route;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final summary = route?.summary;
    if (summary == null) {
      return Text(
        loading ? 'Checking who approves…' : 'Your approver is set by HR.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(fontSize: 10.5, color: RvmColors.subtle),
      );
    }
    final note = route?.routingNoteLabel;
    return TeamNotice(
      icon: Icons.alt_route_rounded,
      tone: TeamPillTone.info,
      text: note == null ? summary : '$summary. $note',
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.controller,
    required this.label,
    required this.onTap,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          readOnly: true,
          onTap: onTap,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Select time',
            prefixIcon: const Icon(Icons.access_time_rounded, size: 19),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: () => controller.clear(),
                    icon: const Icon(Icons.clear_rounded, size: 17),
                  ),
            border: const OutlineInputBorder(),
          ),
        );
      },
    );
  }
}

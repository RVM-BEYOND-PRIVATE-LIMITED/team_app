import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/ess_models.dart';
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
  final _minutes = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _place.dispose();
    _fixIn.dispose();
    _fixOut.dispose();
    _minutes.dispose();
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
    });
  }

  void _setType(String type) {
    setState(() {
      _type = type;
      _error = null;
      _keepDayInWindow();
    });
  }

  /// A fix, an excuse and a short leave describe a day that has happened, so the
  /// server refuses a future one. Keeping the picker inside the same window
  /// avoids a needless 400; on duty and leave may still be filed ahead.
  bool get _mayBeAhead => _family == 'leave' || _type == 'on_duty';

  /// The server's reach-back window: this month, or last month up to the
  /// payroll cut-off (the 5th). A day before it is a 400/409 the picker can
  /// simply not offer.
  DateTime get _firstSelectable {
    final now = DateTime.now();
    return DateTime(now.year, now.month - (now.day <= 5 ? 1 : 0), 1);
  }

  void _keepDayInWindow() {
    final today = DateTime.now();
    if (!_mayBeAhead && _day.isAfter(today)) _day = today;
    if (_day.isBefore(_firstSelectable)) _day = today;
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _dayIso => _iso(_day);
  String get _endDayIso => _iso(_multiDay ? _endDay : _day);

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: _firstSelectable,
      lastDate: _mayBeAhead ? now.add(const Duration(days: 62)) : now,
      helpText: _multiDay ? 'Pick the first day' : 'Pick the day',
    );
    if (picked != null) {
      setState(() {
        _day = picked;
        if (_endDay.isBefore(_day)) _endDay = _day;
        _error = null;
      });
    }
  }

  Future<void> _pickEndDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDay.isBefore(_day) ? _day : _endDay,
      firstDate: _day,
      lastDate: now.add(const Duration(days: 62)),
      helpText: 'Pick the last day',
    );
    if (picked != null) {
      setState(() {
        _endDay = picked;
        _error = null;
      });
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
      if (_multiDay && _endDay.isBefore(_day)) {
        _showError('The last day cannot be before the first day.');
        return;
      }
      if (_portion != 'full' && _multiDay) {
        _showError('A half day is a single day. Choose one day, or a full day.');
        return;
      }
    }
    int? minutes;
    if (_family == 'attendance' && _type == 'short_leave') {
      minutes = int.tryParse(_minutes.text.trim());
      if (minutes == null || minutes < 1 || minutes > 480) {
        _showError('Short leave is 1 to 480 minutes.');
        return;
      }
    }
    final bloc = context.read<RequestsBloc>();
    // The balances on screen are for the CURRENT month. The date picker also
    // allows next month, so only apply this local check when the chosen day is
    // in that same month; otherwise the server decides with its own month data.
    final balance = _balanceFor(bloc.state.balances);
    final remaining = balance?.remaining ??
        (balance?.allowed == null
            ? null
            : balance!.allowed! - balance.used - balance.pending);
    if (balance != null && remaining != null) {
      if (_type == 'short_leave') {
        if (minutes != null && minutes > remaining) {
          _showError(
              'Only $remaining short-leave minutes are left this month.');
          return;
        }
      } else if (_family == 'leave' && !_multiDay) {
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
      if (!r.isPending || r.family != _family || r.type != _type) return false;
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
      minutes: minutes,
    ));
    // Do not pop here: the listeners below pop on success and keep the sheet
    // open on a refusal, with the message inside the sheet where it is visible.
  }

  LeaveBalanceType? _balanceFor(LeaveBalances? balances) {
    if (balances == null) return null;
    // The form may be filed for next month; the shown balances only describe
    // the current month, so they cannot decide that request.
    if (balances.month != _dayIso.substring(0, 7)) return null;
    final key = _family == 'leave' ? 'leave_$_type' : _type;
    for (final type in balances.types) {
      if (type.type == key) return type;
    }
    return null;
  }

  String _formatDays(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  String _limitMessage(LeaveBalanceType balance) {
    final detail =
        '(${_formatDays(balance.used)} used, ${_formatDays(balance.pending)} pending)';
    return switch (_type) {
      'leave_cl' =>
        'You have no casual leave left this month $detail. Choose Leave without pay or another day.',
      'fix_a_day' => "You have reached this month's Fix a Day limit $detail.",
      'excuse_late' =>
        "You have reached this month's Excuse a Late limit $detail.",
      'short_leave' =>
        "You have reached this month's short-leave limit $detail.",
      _ => "You have reached this month's limit for this request $detail.",
    };
  }

  void _showError(String message) {
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final types = _family == 'leave'
        ? const [('cl', 'Casual leave'), ('lwp', 'Leave without pay')]
        : const [
            ('on_duty', 'On duty'),
            ('fix_a_day', 'Fix a day'),
            ('excuse_late', 'Excuse a late'),
            ('short_leave', 'Short leave')
          ];
    final submitting =
        context.select<RequestsBloc, bool>((b) => b.state.submitting);
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
                decoration: const InputDecoration(
                    labelText: 'Type', border: OutlineInputBorder()),
                items: [
                  for (final t in types)
                    DropdownMenuItem(value: t.$1, child: Text(t.$2))
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
                  onSelectionChanged: (s) => setState(() {
                    _multiDay = s.first;
                    _endDay = _day;
                    _error = null;
                  }),
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
                  onSelectionChanged: (s) => setState(() {
                    _portion = s.first;
                    if (_portion != 'full') _multiDay = false;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  _multiDay
                      ? 'Working days are counted when you send. Sundays, weekly offs and holidays are skipped.'
                      : 'A half day counts as 0.5 against the monthly allowance.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: RvmColors.subtle,
                      ),
                ),
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
              if (_type == 'short_leave') ...[
                const SizedBox(height: RvmSpacing.md),
                TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Minutes (1–480)',
                      border: OutlineInputBorder()),
                ),
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

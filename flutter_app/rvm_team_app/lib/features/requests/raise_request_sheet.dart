import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  final _reason = TextEditingController();
  final _place = TextEditingController();
  final _fixIn = TextEditingController();
  final _fixOut = TextEditingController();

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
    });
  }

  String get _dayIso => '${_day.year.toString().padLeft(4, '0')}-'
      '${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 62)),
      lastDate: DateTime.now().add(const Duration(days: 62)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.length < 5) {
      _snack('Please give a reason (at least 5 characters).');
      return;
    }
    if (_family == 'attendance' && _type == 'on_duty' && _place.text.trim().isEmpty) {
      _snack('On duty needs a place.');
      return;
    }
    if (_family == 'attendance' && _type == 'fix_a_day' && _fixIn.text.trim().isEmpty && _fixOut.text.trim().isEmpty) {
      _snack('A fix a day needs a time in or out.');
      return;
    }
    context.read<RequestsBloc>().add(RequestCreateRequested(
          family: _family,
          type: _type,
          day: _dayIso,
          reason: reason,
          place: _type == 'on_duty' ? _place.text.trim() : null,
          fixIn: _type == 'fix_a_day' && _fixIn.text.trim().isNotEmpty ? _fixIn.text.trim() : null,
          fixOut: _type == 'fix_a_day' && _fixOut.text.trim().isNotEmpty ? _fixOut.text.trim() : null,
        ));
    Navigator.of(context).pop();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final types = _family == 'leave'
        ? const [('cl', 'Casual leave'), ('lwp', 'Leave without pay')]
        : const [('on_duty', 'On duty'), ('fix_a_day', 'Fix a day'), ('excuse_late', 'Excuse a late')];
    final submitting = context.select<RequestsBloc, bool>((b) => b.state.submitting);
    return Padding(
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
            Text('New request', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: RvmSpacing.md),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'attendance', label: Text('Attendance'), icon: Icon(Icons.schedule)),
                ButtonSegment(value: 'leave', label: Text('Leave'), icon: Icon(Icons.beach_access_outlined)),
              ],
              selected: {_family},
              onSelectionChanged: (s) => _setFamily(s.first),
            ),
            const SizedBox(height: RvmSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
              items: [for (final t in types) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: RvmSpacing.md),
            OutlinedButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.event),
              label: Text('Day: $_dayIso'),
            ),
            const SizedBox(height: RvmSpacing.md),
            if (_type == 'on_duty')
              TextField(
                controller: _place,
                decoration: const InputDecoration(labelText: 'Place', border: OutlineInputBorder()),
              ),
            if (_type == 'fix_a_day') ...[
              Row(children: [
                Expanded(child: TextField(controller: _fixIn, decoration: const InputDecoration(labelText: 'In (HH:MM)', border: OutlineInputBorder()))),
                const SizedBox(width: RvmSpacing.sm),
                Expanded(child: TextField(controller: _fixOut, decoration: const InputDecoration(labelText: 'Out (HH:MM)', border: OutlineInputBorder()))),
              ]),
            ],
            if (_type == 'on_duty' || _type == 'fix_a_day') const SizedBox(height: RvmSpacing.md),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Reason', alignLabelWithHint: true, border: OutlineInputBorder()),
            ),
            const SizedBox(height: RvmSpacing.sm),
            FilledButton(
              onPressed: submitting ? null : _submit,
              child: submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send to approver'),
            ),
          ],
        ),
      ),
    );
  }
}

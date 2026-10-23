import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../app_feedback.dart';
import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';

/// The Home card's work-from-home flow (KP, 22 Oct 2026): HR enables selected
/// employees with a fixed monthly limit; the employee sees what is left and files
/// a whole day through the normal leave request and approval chain.
Future<void> showWfhSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _WfhSheet(),
    );

class _WfhSheet extends StatefulWidget {
  const _WfhSheet();

  @override
  State<_WfhSheet> createState() => _WfhSheetState();
}

class _WfhSheetState extends State<_WfhSheet> {
  late Future<WfhAllowance> _future;
  final _reason = TextEditingController();
  DateTime _day = DateTime.now();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = getIt<EssRepository>().myWfh();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String get _dayIso => '${_day.year.toString().padLeft(4, '0')}-'
      '${_day.month.toString().padLeft(2, '0')}-'
      '${_day.day.toString().padLeft(2, '0')}';

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isBefore(now) ? now : _day,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year, now.month + 1, 0),
    );
    if (picked != null) setState(() => _day = picked);
  }

  void _snack(String message) => showAppMessage(message);

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.length < 5) {
      _snack('Please give a reason (at least 5 characters).');
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final result = await getIt<EssRepository>().createLeaveRequestSafe(
      type: 'wfh',
      day: _dayIso,
      reason: reason,
    );
    if (!mounted) return;
    if (result.failure != null) {
      setState(() => _submitting = false);
      _snack(result.failure!.message);
      return;
    }
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
          const SnackBar(content: Text('Work-from-home request sent.')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: RvmSpacing.md,
        right: RvmSpacing.md,
        top: RvmSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + RvmSpacing.lg,
      ),
      child: FutureBuilder<WfhAllowance>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
                height: 140, child: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            final message = error is Failure
                ? error.message
                : 'Could not load your work-from-home allowance. Try again.';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Work from home',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: RvmSpacing.sm),
                Text(message),
                const SizedBox(height: RvmSpacing.md),
                TextButton(
                  onPressed: () =>
                      setState(() => _future = getIt<EssRepository>().myWfh()),
                  child: const Text('Retry'),
                ),
              ],
            );
          }
          final allowance = snapshot.data!;
          if (!allowance.enabled) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Work from home',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: RvmSpacing.sm),
                const Text(
                    'Work from home is not offered for your login. Ask HR if it should be.'),
                const SizedBox(height: RvmSpacing.md),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          }
          final noDaysLeft = allowance.remaining <= 0;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Work from home',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: RvmSpacing.xs),
                Text(
                  '${allowance.remaining} of ${allowance.monthlyLimitDays} days left this month'
                  ' (${allowance.used} used, ${allowance.pending} pending)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: RvmSpacing.md),
                OutlinedButton.icon(
                  onPressed: noDaysLeft ? null : _pickDay,
                  icon: const Icon(Icons.event),
                  label: Text('Day: $_dayIso'),
                ),
                const SizedBox(height: RvmSpacing.md),
                TextField(
                  controller: _reason,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: RvmSpacing.sm),
                FilledButton(
                  onPressed: noDaysLeft || _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(noDaysLeft
                          ? 'No days left this month'
                          : 'Request WFH day'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

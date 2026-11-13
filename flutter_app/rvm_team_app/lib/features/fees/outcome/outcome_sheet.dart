import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../../widgets/team_kit.dart';
import 'followup_outcome.dart';
import 'outcome_rules.dart';

/// Opens the outcome form for a fees follow-up call (team_app #53, item 8)
/// and returns what was entered when Save is tapped, or null when the sheet
/// is closed without saving.
///
/// It is not wired to a screen or a save yet: the dialer opens it once
/// Scheduler_Backend#176 has the endpoint. [clock] is the device clock unless
/// a test passes one; only its instant is read, so "today" is IST whatever
/// the phone's time zone.
Future<FollowupOutcomeDraft?> showFollowupOutcomeSheet(
  BuildContext context, {
  DateTime Function()? clock,
}) =>
    showModalBottomSheet<FollowupOutcomeDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FollowupOutcomeSheet(clock: clock),
    );

/// The outcome form: Answered or No Answer (required), a remark (optional)
/// and the next follow-up date (optional, tomorrow or later in IST, the
/// Scheduler's rule in `outcome_rules.dart`).
///
/// The sheet makes one idempotency key when it opens, and every Save of it
/// carries that key; another sheet makes another key.
class FollowupOutcomeSheet extends StatefulWidget {
  const FollowupOutcomeSheet({super.key, this.clock, this.onSave});

  /// As in [showFollowupOutcomeSheet].
  final DateTime Function()? clock;

  /// Takes each Save instead of closing the sheet, for a caller that saves
  /// while the sheet stays open so a failed save can be tried again from it
  /// with the same key. Without it, Save closes the sheet with the draft.
  final ValueChanged<FollowupOutcomeDraft>? onSave;

  @override
  State<FollowupOutcomeSheet> createState() => _FollowupOutcomeSheetState();
}

class _FollowupOutcomeSheetState extends State<FollowupOutcomeSheet> {
  /// The Scheduler sets no latest next follow-up date; the calendar needs
  /// one, so it ends far enough out never to be the limit.
  static final _lastDay = DateTime(2100, 12, 31);

  /// Icon buttons are 40 px by default and padded to a larger target only on
  /// some platforms; these are 44 px everywhere.
  static final _iconTarget =
      IconButton.styleFrom(minimumSize: const Size.square(44));

  late final String _key;
  final _remark = TextEditingController();
  FollowupOutcome? _outcome;
  DateTime? _nextDate;
  String? _dateError;

  /// Set by the Save that closes the sheet, so a second Save before the sheet
  /// is gone cannot close the screen under it as well. Flutter drops a second
  /// touch itself, but not a screen reader's or a keyboard's activate.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _key = IdempotencyInterceptor.newKey();
  }

  @override
  void dispose() {
    _remark.dispose();
    super.dispose();
  }

  DateTime _nowUtc() => (widget.clock ?? DateTime.now)().toUtc();

  Future<void> _pickDate() async {
    final now = _nowUtc();
    final first = istTomorrow(now);
    final chosen = _nextDate;
    final picked = await showDatePicker(
      context: context,
      helpText: 'Next follow-up',
      firstDate: first,
      lastDate: _lastDay,
      initialDate: chosen == null || chosen.isBefore(first) ? first : chosen,
      currentDate: istToday(now),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _nextDate = DateUtils.dateOnly(picked);
      _dateError = null;
    });
  }

  void _clearDate() => setState(() {
        _nextDate = null;
        _dateError = null;
      });

  void _save() {
    final outcome = _outcome;
    if (outcome == null || _closing) return;
    // Checked again here: a day picked as "tomorrow" before midnight is
    // today once midnight has passed, and the Scheduler would refuse it.
    final error = validateNextFollowUpDate(_nextDate, nowUtc: _nowUtc());
    if (error != null) {
      setState(() => _dateError = error);
      return;
    }
    final draft = FollowupOutcomeDraft(
      outcome: outcome,
      remark: _remark.text.trim(),
      nextDate: _nextDate,
      idempotencyKey: _key,
    );
    final onSave = widget.onSave;
    if (onSave != null) {
      onSave(draft);
      return;
    }
    _closing = true;
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final date = _nextDate;
    final dateError = _dateError;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              RvmSpacing.md, 0, RvmSpacing.md, RvmSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TeamSheetHeader(
                title: 'Call outcome',
                icon: Icons.phone_in_talk_rounded,
                // The kit's own close button is compact; this one keeps the
                // 44 px touch target.
                trailing: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  style: _iconTarget,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ),
              const SizedBox(height: RvmSpacing.xs),
              Text('How did the call go?', style: small),
              const SizedBox(height: RvmSpacing.md),
              const TeamFieldLabel('Outcome'),
              const SizedBox(height: RvmSpacing.sm),
              _OutcomeChoice(
                selected: _outcome,
                onChanged: (o) => setState(() => _outcome = o),
              ),
              const SizedBox(height: RvmSpacing.md),
              const TeamFieldLabel('Remark (optional)'),
              const SizedBox(height: RvmSpacing.sm),
              TextField(
                controller: _remark,
                minLines: 3,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'What was said on the call'),
              ),
              const SizedBox(height: RvmSpacing.md),
              const TeamFieldLabel('Next follow-up (optional)'),
              const SizedBox(height: RvmSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event_rounded),
                      label: Text(
                          date == null ? 'Pick a date' : _dayLabel(date)),
                    ),
                  ),
                  if (date != null) ...[
                    const SizedBox(width: RvmSpacing.xs),
                    IconButton(
                      tooltip: 'Clear date',
                      onPressed: _clearDate,
                      style: _iconTarget,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              if (dateError != null)
                TeamNotice(
                  icon: Icons.error_outline_rounded,
                  tone: TeamPillTone.danger,
                  text: dateError,
                )
              else
                Text('Tomorrow or later.', style: small),
              const SizedBox(height: RvmSpacing.lg),
              if (_outcome == null) ...[
                Text(
                  'Choose ${FollowupOutcome.answered.label} or '
                  '${FollowupOutcome.noAnswer.label} to save.',
                  textAlign: TextAlign.center,
                  style: small,
                ),
                const SizedBox(height: RvmSpacing.sm),
              ],
              FilledButton.icon(
                onPressed: _outcome == null ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Fri, Nov 20, 2026": the year too, since the next follow-up can fall in
  /// the next one.
  String _dayLabel(DateTime d) {
    final l = MaterialLocalizations.of(context);
    return '${l.formatMediumDate(d)}, ${l.formatYear(d)}';
  }
}

/// The two outcomes, side by side when both labels fit on one line, and one
/// above the other on a narrow phone or with large text.
class _OutcomeChoice extends StatelessWidget {
  const _OutcomeChoice({required this.selected, required this.onChanged});

  /// A tile's fixed parts: padding, icon tile, gaps, radio mark and border.
  static const _tileChrome = 104.0;

  /// The longer label, "No Answer", at text size x1.
  static const _labelWidth = 80.0;

  final FollowupOutcome? selected;
  final ValueChanged<FollowupOutcome> onChanged;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(builder: (context, constraints) {
      final options = [
        for (final o in FollowupOutcome.values)
          _OutcomeOption(
            outcome: o,
            selected: o == selected,
            onTap: () => onChanged(o),
          ),
      ];
      final sideBySide = constraints.maxWidth >=
          2 * (_tileChrome + _labelWidth * scale) + RvmSpacing.sm;
      if (sideBySide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: options[0]),
            const SizedBox(width: RvmSpacing.sm),
            Expanded(child: options[1]),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          options[0],
          const SizedBox(height: RvmSpacing.sm),
          options[1],
        ],
      );
    });
  }
}

class _OutcomeOption extends StatelessWidget {
  const _OutcomeOption({
    required this.outcome,
    required this.selected,
    required this.onTap,
  });

  final FollowupOutcome outcome;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, tone, soft) = switch (outcome) {
      FollowupOutcome.answered => (
          Icons.call_rounded,
          RvmColors.success,
          RvmColors.successSoft
        ),
      FollowupOutcome.noAnswer => (
          Icons.phone_missed_rounded,
          RvmColors.warning,
          RvmColors.warningSoft
        ),
    };
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: TeamCard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: selected ? scheme.primaryContainer : null,
          borderColor: selected ? scheme.primary : null,
          child: Row(
            children: [
              TeamIconBadge(
                icon: icon,
                color: tone,
                background: soft,
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  outcome.label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

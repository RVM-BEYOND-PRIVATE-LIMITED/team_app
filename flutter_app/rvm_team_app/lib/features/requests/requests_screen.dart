import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import '../../widgets/team_kit.dart';
import 'bloc/requests_bloc.dart';
import 'raise_request_sheet.dart';

/// C1–C5: my requests (on duty, fix a day, excuse a late, CL, leave without pay), the month's
/// balances, raise and withdraw. Backend: `/attendance-requests`, `/leave-requests`,
/// `/leave/balances` (Phase 1C).
class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<RequestsBloc>()..add(const RequestsLoadRequested()),
      child: BlocProvider(
        // This route is pushed outside the shell, so it brings its own copy of
        // the menu. The Team Approvals tab is only shown to somebody the server
        // will actually let decide: the Inbox otherwise opens on a 403.
        create: (_) => getIt<CapabilitiesBloc>()..add(const LoadRequested()),
        child: const _RequestsView(),
      ),
    );
  }
}

class _RequestsView extends StatelessWidget {
  const _RequestsView();

  @override
  Widget build(BuildContext context) {
    final caps = context.watch<CapabilitiesBloc>().state.data;
    final canApprove =
        caps?.approvalsOwnReports == true || caps?.approvalsAnyRequest == true;
    return Scaffold(
      backgroundColor: RvmColors.ivory,
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Time & Leave',
            subtitle: const Text('Attendance fixes, leaves & duty records'),
            actions: [
              TeamHeaderAction(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onPressed: () =>
                    context.read<RequestsBloc>().add(const RequestsRefreshed()),
              ),
            ],
            footer: TeamSegmentedTabs(
              labels: canApprove
                  ? const ['My Requests', 'Team Approvals']
                  : const ['My Requests'],
              selectedIndex: 0,
              onDark: true,
              onChanged: (i) {
                if (i == 1 && canApprove) context.push('/approvals');
              },
            ),
          ),
          Expanded(
            // Two listeners, not one: clearing a failure while retrying must
            // not look like a success (the old single listener did that when
            // createdNonce was already above zero from an earlier request).
            child: BlocListener<RequestsBloc, RequestsState>(
              listenWhen: (a, b) => a.submitFailure != b.submitFailure,
              listener: (context, state) {
                final msg = state.submitFailure?.message;
                if (msg != null) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(msg)));
                }
              },
              child: BlocListener<RequestsBloc, RequestsState>(
                listenWhen: (a, b) => a.createdNonce != b.createdNonce,
                listener: (context, state) {
                  if (state.createdNonce == 0) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(
                        content: Text('Request sent to your approver.')));
                },
                child: BlocBuilder<RequestsBloc, RequestsState>(
                  builder: (context, state) => _body(context, state),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton.extended(
          backgroundColor: RvmColors.clay,
          foregroundColor: Colors.white,
          onPressed: () => showRaiseRequestSheet(context),
          icon: const Icon(Icons.add_rounded, size: 19),
          label: const Text('New Request',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, RequestsState state) {
    if (state.status == LoadStatus.initial ||
        state.status == LoadStatus.loading) {
      return const AppLoading();
    }
    if (state.status == LoadStatus.failure) {
      return AppError(
        message: state.failure?.message ?? 'Could not load your requests.',
        onRetry: () =>
            context.read<RequestsBloc>().add(const RequestsRefreshed()),
      );
    }
    final active = state.requests.where((r) => r.isPending).length;
    return RefreshIndicator(
      color: RvmColors.clay,
      onRefresh: () async =>
          context.read<RequestsBloc>().add(const RequestsRefreshed()),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, 96),
        children: [
          if (state.balances != null) _QuotaCard(balances: state.balances!),
          const SizedBox(height: RvmSpacing.lg),
          TeamSectionHeader(
            title: 'My Requests',
            count: active > 0 ? '$active Active' : null,
            trailing: TextButton(
              onPressed: () => _history(context, state.requests),
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28), padding: EdgeInsets.zero),
              child: Row(
                children: [
                  Text('History',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: RvmColors.clay,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 12, color: RvmColors.clay),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (state.requests.isEmpty)
            TeamCard(
              child: Column(
                children: [
                  const Icon(Icons.event_note_outlined,
                      size: 30, color: RvmColors.subtle),
                  const SizedBox(height: 8),
                  Text('No requests yet.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text('Raise a request and it will appear here.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontSize: 10, color: RvmColors.subtle)),
                ],
              ),
            )
          else
            for (final r in state.requests) ...[
              _RequestCard(request: r),
              const SizedBox(height: RvmSpacing.sm),
            ],
        ],
      ),
    );
  }

  void _history(BuildContext context, List<EssRequest> requests) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
          children: [
            TeamSheetHeader(
              title: 'Request history',
              icon: Icons.history_rounded,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 12),
            for (final r in requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RequestCard(request: r, compact: true),
              ),
          ],
        ),
      ),
    );
  }
}

// ── quota ─────────────────────────────────────────────────────────────────

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.balances});
  final LeaveBalances balances;

  @override
  Widget build(BuildContext context) {
    final offered = balances.types.where((t) => t.offered).toList();
    final cl = _find(offered, const ['leave_cl']);
    final late = _find(offered, const ['excuse_late']);
    final short = _find(offered, const ['short_leave']);
    final fix = _find(offered, const ['fix_a_day']);
    final onDuty = _find(balances.types, const ['on_duty']);
    final lwp = _find(balances.types, const ['leave_lwp']);
    final month = _prettyMonth(balances.month);

    return TeamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: RvmColors.success, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text('Monthly Quota',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Flexible(
                child: Text('• $month',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 9.5, color: RvmColors.subtle)),
              ),
              const Spacer(),
              const TeamPill(
                  label: 'Auto-renews next month',
                  tone: TeamPillTone.neutral,
                  dense: true),
            ],
          ),
          const SizedBox(height: 12),
          if (offered.isEmpty)
            Text('No request types are available to your login.',
                style: Theme.of(context).textTheme.bodySmall)
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _quotaTile(
                        context, cl, 'Casual Leave', RvmColors.clay)),
                const SizedBox(width: 8),
                Expanded(
                    child: _quotaTile(
                        context, late, 'Excuse Late', RvmColors.teamSeed,
                        showPending: true)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _quotaTile(
                        context, short, 'Short Leave', RvmColors.clay,
                        unitMinutes: true)),
                const SizedBox(width: 8),
                Expanded(
                    child: _quotaTile(context, fix, 'Fix a Day', RvmColors.clay,
                        available: true)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _secondaryUsage(context, 'On Duty', onDuty?.used ?? 0),
                ),
                Container(width: 1, height: 16, color: RvmColors.line),
                Expanded(
                    child: _secondaryUsage(
                        context, 'Without Pay', lwp?.used ?? 0)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  LeaveBalanceType? _find(List<LeaveBalanceType> types, List<String> keys) {
    for (final t in types) {
      if (keys.contains(t.type)) return t;
    }
    return null;
  }

  Widget _quotaTile(
    BuildContext context,
    LeaveBalanceType? t,
    String title,
    Color accent, {
    bool showPending = false,
    bool unitMinutes = false,
    bool available = false,
  }) {
    final allowed = t?.allowed;
    final remaining =
        t?.remaining ?? (allowed == null ? null : allowed - (t?.used ?? 0));
    final used = t?.used ?? 0;
    final progress =
        (allowed == null || allowed == 0) ? 0.0 : ((remaining ?? 0) / allowed);
    final value = unitMinutes
        ? '${remaining ?? used}'
        : '${remaining ?? allowed ?? used}';
    final suffix = unitMinutes
        ? '/ ${allowed ?? '—'} mins'
        : available
            ? '/ ${allowed ?? '—'} available'
            : '/ ${allowed ?? '—'} ${allowed == 1 ? 'day' : 'days'} left';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: RvmColors.cream,
        borderRadius: BorderRadius.circular(RvmRadii.md),
        border: Border.all(color: RvmColors.sand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontSize: 11.5)),
              ),
              if (showPending && (t?.pending ?? 0) > 0)
                TeamPill(
                    label: '${t!.pending} Pending',
                    tone: TeamPillTone.warning,
                    dense: true)
              else if (available)
                Text('/ ${allowed ?? '—'}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontSize: 9, color: RvmColors.subtle)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 19,
                        color: used > 0 && remaining == 0
                            ? RvmColors.danger
                            : RvmColors.ink,
                      )),
              const SizedBox(width: 3),
              Flexible(
                child: Text(suffix,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 8.5, color: RvmColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TeamProgressBar(value: progress, color: accent),
        ],
      ),
    );
  }

  Widget _secondaryUsage(BuildContext context, String label, int used) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
              color: RvmColors.subtle, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text('$label: ',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontSize: 9.5, color: RvmColors.subtle)),
        Text('$used used',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9.5,
                color: RvmColors.muted,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  String _prettyMonth(String value) {
    final date = DateTime.tryParse('$value-01');
    if (date == null) return value;
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
      'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

// ── request card ──────────────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, this.compact = false});
  final EssRequest request;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (request.status) {
      'approved' => ('Approved', TeamPillTone.success),
      'rejected' => ('Rejected', TeamPillTone.danger),
      'withdrawn' => ('Withdrawn', TeamPillTone.neutral),
      'cancelled' => ('Cancelled', TeamPillTone.neutral),
      _ => ('Pending Review', TeamPillTone.warning),
    };
    final (icon, color, soft) = _typeStyle(request.type);
    final submitted = request.createdAt == null
        ? null
        : 'Submitted ${_monthDay(request.createdAt!)}';
    return TeamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TeamIconBadge(
                  icon: icon,
                  color: color,
                  background: soft,
                  size: 36,
                  iconSize: 17,
                  radius: 11),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.typeLabel,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 1),
                    Text(_typeSubtitle(request),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 9.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TeamPill(label: label, tone: tone, dense: true),
            ],
          ),
          if (!compact && request.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: RvmColors.cream,
                borderRadius: BorderRadius.circular(RvmRadii.sm),
              ),
              child: Text('“${request.reason.trim()}”',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        fontStyle: FontStyle.italic,
                        height: 1.45,
                        color: RvmColors.muted,
                      )),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (submitted != null) ...[
                const Icon(Icons.schedule_rounded,
                    size: 11, color: RvmColors.subtle),
                const SizedBox(width: 4),
                Text(submitted,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 9, color: RvmColors.subtle)),
              ],
              const Spacer(),
              if (request.isPending)
                GestureDetector(
                  onTap: () => context.read<RequestsBloc>().add(
                      RequestWithdrawRequested(
                          family: request.family, id: request.id)),
                  child: Row(
                    children: [
                      const Icon(Icons.undo_rounded,
                          size: 12, color: RvmColors.muted),
                      const SizedBox(width: 4),
                      Text('Withdraw',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontSize: 10.5,
                                    color: RvmColors.muted,
                                    fontWeight: FontWeight.w600,
                                  )),
                    ],
                  ),
                )
              else
                Text(_decisionText(request),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 9, color: RvmColors.subtle)),
            ],
          ),
        ],
      ),
    );
  }

  (IconData, Color, Color) _typeStyle(String type) => switch (type) {
        'cl' || 'leave_cl' => (
            Icons.calendar_today_rounded,
            RvmColors.warning,
            RvmColors.warningSoft
          ),
        'lwp' || 'leave_lwp' => (
            Icons.event_busy_rounded,
            RvmColors.muted,
            RvmColors.cream
          ),
        'excuse_late' => (
            Icons.access_time_rounded,
            RvmColors.teamSeed,
            const Color(0xFFFCEBE2)
          ),
        'fix_a_day' => (
            Icons.build_circle_outlined,
            RvmColors.info,
            RvmColors.infoSoft
          ),
        'on_duty' => (
            Icons.work_outline_rounded,
            RvmColors.success,
            RvmColors.successSoft
          ),
        _ => (Icons.event_note_outlined, RvmColors.clay, RvmColors.claySoft),
      };

  String _typeSubtitle(EssRequest r) {
    final parts = <String>[];
    if (r.place != null && r.place!.isNotEmpty) parts.add(r.place!);
    parts.add(_prettyDate(r.day));
    if (r.context?.othersOffCount != null && r.context!.othersOffCount > 0) {
      parts.add('${r.context!.othersOffCount} others off');
    }
    return parts.join(' • ');
  }

  String _decisionText(EssRequest r) {
    if (r.decidedByName != null) return 'by ${r.decidedByName}';
    if (r.decisionNote != null) return r.decisionNote!;
    return '';
  }

  String _prettyDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return _monthDay(date);
  }

  String _monthDay(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

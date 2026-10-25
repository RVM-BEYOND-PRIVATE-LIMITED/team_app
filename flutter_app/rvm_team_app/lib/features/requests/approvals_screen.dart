import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import '../../widgets/team_kit.dart';
import 'bloc/approvals_bloc.dart';

/// D1/H6: the approvals Inbox — a manager's own reports, or HR-wide. Backend: `/api/ess/approvals`.
class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<ApprovalsBloc>()..add(const ApprovalsLoadRequested()),
      child: BlocProvider(
        // Needed to know whether this caller may ask the server for decided
        // requests. A manager's Inbox is pending-only on the live API, so the
        // status pills are hidden rather than opening a 403.
        create: (_) => getIt<CapabilitiesBloc>()..add(const LoadRequested()),
        child: const _ApprovalsView(),
      ),
    );
  }
}

class _ApprovalsView extends StatelessWidget {
  const _ApprovalsView();

  @override
  Widget build(BuildContext context) {
    final hrWide =
        context.watch<CapabilitiesBloc>().state.data?.approvalsAnyRequest ==
            true;
    return Scaffold(
      backgroundColor: RvmColors.ivory,
      body: Column(
        children: [
          BlocBuilder<ApprovalsBloc, ApprovalsState>(
            buildWhen: (a, b) => a.inbox?.total != b.inbox?.total,
            builder: (context, state) {
              final total = state.inbox?.total;
              return TeamPageHeader(
                title: 'Approvals',
                titleTrailing: total == null || total == 0
                    ? null
                    : TeamPill(
                        label: '$total Pending',
                        tone: TeamPillTone.onDark,
                        dense: true),
                subtitle: const Text('Review and decide team requests'),
                actions: [
                  TeamHeaderAction(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh',
                    onPressed: () => context
                        .read<ApprovalsBloc>()
                        .add(const ApprovalsRefreshed()),
                  ),
                ],
                footer: TeamSegmentedTabs(
                  labels: const ['My Requests', 'Team Approvals'],
                  selectedIndex: 1,
                  onDark: true,
                  onChanged: (i) {
                    if (i == 0) context.pop();
                  },
                ),
              );
            },
          ),
          Expanded(
            child: BlocConsumer<ApprovalsBloc, ApprovalsState>(
              listenWhen: (a, b) =>
                  a.decidedNonce != b.decidedNonce ||
                  a.actionFailure != b.actionFailure,
              listener: (context, state) {
                final msg = state.actionFailure?.message;
                if (msg != null) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(msg)));
                } else if (state.decidedNonce > 0) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                        const SnackBar(content: Text('Decision saved.')));
                }
              },
              builder: (context, state) =>
                  _body(context, state, hrWide: hrWide),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ApprovalsState state,
      {required bool hrWide}) {
    if (state.status == LoadStatus.initial ||
        (state.status == LoadStatus.loading && state.inbox == null)) {
      return const AppLoading();
    }
    if (state.status == LoadStatus.failure && state.inbox == null) {
      return AppError(
        message: state.failure?.message ?? 'Could not load approvals.',
        onRetry: () =>
            context.read<ApprovalsBloc>().add(const ApprovalsRefreshed()),
      );
    }
    final inbox = state.inbox;
    return Column(
      children: [
        const SizedBox(height: 12),
        _FilterRow(
          selected: state.filter,
          inbox: inbox,
          showAllStatuses: hrWide,
          onSelected: (f) =>
              context.read<ApprovalsBloc>().add(ApprovalsFiltered(f)),
        ),
        if (inbox != null)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(RvmSpacing.md, 14, RvmSpacing.md, 4),
            child: Row(
              children: [
                _SyncStat(
                    label: 'ATTENDANCE',
                    value: '${inbox.attendance} REGULARIZATION'),
                const SizedBox(width: 18),
                _SyncStat(label: 'LEAVE', value: '${inbox.leave} REQUEST'),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('SYNCED',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 8,
                            letterSpacing: 0.6,
                            color: RvmColors.subtle)),
                    Text('JUST NOW',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 8,
                            letterSpacing: 0.6,
                            color: RvmColors.subtle)),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: inbox == null || inbox.requests.isEmpty
              ? const AppEmpty(
                  icon: Icons.task_alt, message: 'Nothing to decide here.')
              : RefreshIndicator(
                  color: RvmColors.clay,
                  onRefresh: () async => context
                      .read<ApprovalsBloc>()
                      .add(const ApprovalsRefreshed()),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(RvmSpacing.md,
                        RvmSpacing.sm, RvmSpacing.md, RvmSpacing.lg),
                    itemCount: inbox.requests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _ApprovalCard(
                        request: inbox.requests[i], hrWide: hrWide),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SyncStat extends StatelessWidget {
  const _SyncStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 3),
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
              color: RvmColors.subtle, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 7.5,
                    letterSpacing: 0.7,
                    color: RvmColors.subtle)),
            Text(value,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 8,
                    letterSpacing: 0.4,
                    color: RvmColors.muted,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow(
      {required this.selected,
      required this.onSelected,
      required this.showAllStatuses,
      this.inbox});
  final String selected;
  final ApprovalInbox? inbox;
  final ValueChanged<String> onSelected;

  /// HR-wide callers may ask for any status; a manager's live Inbox is
  /// pending-only, so showing the other pills would only produce a 403.
  final bool showAllStatuses;

  @override
  Widget build(BuildContext context) {
    final pending = inbox?.total;
    final items = <(String, String, String?)>[
      ('pending', 'Pending', pending == null ? null : '$pending'),
      if (showAllStatuses) ...[
        (
          'approved',
          'Approved',
          selected == 'approved' && inbox != null
              ? '${inbox!.requests.length}'
              : null
        ),
        (
          'rejected',
          'Rejected',
          selected == 'rejected' && inbox != null
              ? '${inbox!.requests.length}'
              : null
        ),
        ('all', 'All', null),
      ],
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: RvmSpacing.md),
      child: Row(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterPill(
                label: item.$2,
                count: item.$3,
                selected: selected == item.$1,
                onTap: () => onSelected(item.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.count});
  final String label;
  final String? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? RvmColors.claySoft : RvmColors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected
                    ? RvmColors.clay.withValues(alpha: 0.30)
                    : RvmColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded,
                    size: 12, color: RvmColors.clay),
                const SizedBox(width: 4),
              ],
              Text(
                count == null ? label : '$label ($count)',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 11,
                      color: selected ? RvmColors.clay : RvmColors.muted,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.request, required this.hrWide});
  final EssRequest request;

  /// HR, the CEO and super admins may decide any request, so a faculty leave
  /// they open is finalised in one step; only a manager sees "Send to HR".
  final bool hrWide;

  /// True only for a manager's first round on a faculty member's leave.
  bool get _advanceOnly =>
      request.requiresFinalApproval && request.stage == 'manager' && !hrWide;

  @override
  Widget build(BuildContext context) {
    final ctx = request.context;
    final employee = request.employee?.fullName ?? 'Employee';
    final isLeave = request.family == 'leave';
    final date = isLeave ? request.dateLabel : _prettyDate(request.day);
    final typeChip = _typeChip(request);
    final category = isLeave
        ? '${request.daysLabel}${request.isHalfDay ? ' · ${request.portionLabel}' : ''}'
        : 'Regularization';
    final contextLine = ctx == null
        ? null
        : [
            if (ctx.typeThisMonth > 0 && ctx.monthLimit != null)
              '${ctx.typeThisMonth} of ${ctx.monthLimit} ${isLeave ? 'this month' : 'late excuses used this month'}',
            if (ctx.othersOffCount > 0) '${ctx.othersOffCount} others off',
          ].where((s) => s.isNotEmpty).join(' · ');

    return TeamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TeamAvatar(
                  name: employee.toUpperCase(),
                  size: 36,
                  background: RvmColors.sand,
                  foreground: RvmColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(employee,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 1),
                    Text(
                      [
                        if (request.employee?.employeeCode != null)
                          request.employee!.employeeCode!,
                        if (isLeave) 'Leave' else 'Attendance'
                      ].join(' • '),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontSize: 9.5, color: RvmColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              TeamPill(label: date, tone: TeamPillTone.neutral, dense: true),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCF0E8),
                  borderRadius: BorderRadius.circular(RvmRadii.xs),
                  border: Border.all(color: const Color(0xFFF5DECE)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(typeChip.$1, size: 11, color: RvmColors.clay),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(typeChip.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontSize: 9.5,
                                    color: RvmColors.clay,
                                    fontWeight: FontWeight.w600,
                                  )),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 9.5, color: RvmColors.subtle)),
              ),
            ],
          ),
          if (request.requiresFinalApproval) ...[
            const SizedBox(height: 6),
            TeamPill(
                label: request.stage == 'final'
                    ? 'Final round · HR / CEO / Superadmin'
                    : 'First round · manager',
                tone: request.stage == 'final'
                    ? TeamPillTone.warning
                    : TeamPillTone.neutral,
                dense: true),
          ],
          if (request.managerRemark != null &&
              request.managerRemark!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Manager’s remark: ${request.managerRemark!.trim()}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                      color: RvmColors.teamSeed,
                      fontWeight: FontWeight.w600,
                    )),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: RvmColors.cream,
              borderRadius: BorderRadius.circular(RvmRadii.sm),
            ),
            child: Text('“${request.reason.trim()}”',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                      color: RvmColors.muted,
                    )),
          ),
          if (request.decisionNote != null &&
              request.decisionNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Final remark: ${request.decisionNote!.trim()}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                      height: 1.45,
                      color: RvmColors.teamSeed,
                      fontWeight: FontWeight.w600,
                    )),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (contextLine != null)
                Flexible(
                  child: Text(contextLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontSize: 9, color: RvmColors.muted)),
                ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showChain(context),
                child: Row(
                  children: [
                    Text('Approval chain',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  fontSize: 9.5,
                                  color: RvmColors.clay,
                                  fontWeight: FontWeight.w600,
                                )),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 11, color: RvmColors.clay),
                  ],
                ),
              ),
            ],
          ),
          if (request.status == 'pending') ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _reject(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      foregroundColor: RvmColors.ink,
                    ),
                    child: const Text('Reject',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _approve(context),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(40)),
                    child: Text(_advanceOnly ? 'Send to HR' : 'Approve',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ] else
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  if (request.status == 'approved')
                    TextButton(
                      onPressed: () => _cancel(context),
                      style: TextButton.styleFrom(
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          foregroundColor: RvmColors.muted),
                      child: const Text('Cancel (HR)',
                          style: TextStyle(fontSize: 10.5)),
                    ),
                  TextButton(
                    onPressed: () => context.read<ApprovalsBloc>().add(
                        ApprovalArchived(
                            family: request.family, id: request.id)),
                    style: TextButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        foregroundColor: RvmColors.muted),
                    child:
                        const Text('Archive', style: TextStyle(fontSize: 10.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  (IconData, String) _typeChip(EssRequest r) {
    final late = r.context?.late?.lateMinutes;
    final leaveDetail = r.isHalfDay ? r.portionLabel : r.daysLabel;
    return switch (r.type) {
      'cl' => (Icons.calendar_today_rounded, 'Casual Leave ($leaveDetail)'),
      'lwp' => (Icons.event_busy_rounded, 'Leave Without Pay ($leaveDetail)'),
      'excuse_late' => (
          Icons.access_time_rounded,
          late == null ? 'Late Punch In' : 'Late Punch In ($late mins late)'
        ),
      'fix_a_day' => (Icons.build_circle_outlined, 'Fix a Day'),
      'on_duty' => (Icons.work_outline_rounded, 'On Duty'),
      _ => (Icons.event_note_outlined, r.typeLabel),
    };
  }

  String _prettyDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
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

  Future<void> _showChain(BuildContext context) async {
    try {
      final chain = await getIt<EssRepository>()
          .approvalChain(request.family, request.id);
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Approval chain'),
          content: SizedBox(
            width: 360,
            child: chain.chain.isEmpty
                ? Text(chain.hrFallback
                    ? 'HR decides this one.'
                    : 'No chain recorded.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final e in chain.chain)
                        ListTile(
                          dense: true,
                          leading: Icon(
                              e.mayDecide
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: e.mayDecide ? RvmColors.success : null),
                          title: Text(e.employee.fullName),
                          subtitle: e.skipped == null
                              ? null
                              : Text('skipped: ${e.skipped}'),
                        ),
                      if (chain.hrFallback)
                        const ListTile(dense: true, title: Text('HR fallback')),
                    ],
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'))
          ],
        ),
      );
    } on Failure catch (f) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(f.message)));
      }
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this approved request'),
        content: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'Reason (at least 3 characters)')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Back')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Cancel request')),
        ],
      ),
    );
    if (reason == null || reason.length < 3 || !context.mounted) return;
    try {
      await getIt<EssRepository>()
          .cancelRequest(request.family, request.id, reason);
      if (context.mounted) {
        context.read<ApprovalsBloc>().add(const ApprovalsRefreshed());
      }
    } on Failure catch (f) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(f.message)));
      }
    }
  }

  /// Approving opens a small remark box: the manager's word travels with the decision and
  /// the employee reads it on the request card. A remark is optional to approve.
  Future<void> _approve(BuildContext context) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_advanceOnly
            ? 'Approve and send to HR'
            : 'Approve this leave'),
        content: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            decoration: InputDecoration(
                labelText: _advanceOnly
                    ? 'Manager’s remark (optional)'
                    : 'Final approval remark (optional)',
                alignLabelWithHint: true,
                hintText: 'Anything the employee should know')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Back')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(_advanceOnly ? 'Send to HR' : 'Approve leave')),
        ],
      ),
    );
    if (note == null || !context.mounted) return;
    context.read<ApprovalsBloc>().add(ApprovalDecided(
        family: request.family,
        id: request.id,
        decision: 'approve',
        note: note.isEmpty ? null : note));
  }

  Future<void> _reject(BuildContext context) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reason to reject'),
        content: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            decoration:
                const InputDecoration(hintText: 'At least 3 characters')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Reject')),
        ],
      ),
    );
    if (note == null || !context.mounted) return;
    if (note.length < 3) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Please give a reason.')));
      return;
    }
    context.read<ApprovalsBloc>().add(ApprovalDecided(
        family: request.family,
        id: request.id,
        decision: 'reject',
        note: note));
  }
}

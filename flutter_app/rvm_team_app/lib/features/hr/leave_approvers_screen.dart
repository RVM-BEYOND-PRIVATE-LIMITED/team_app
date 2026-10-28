import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';

/// HRMS Leaves settings (issue #33): a super admin chooses the branch Admin
/// Manager who decides leave first, before the super-admin final round.
/// Backend: `GET/PUT /api/ess/leave-approvers`.
class LeaveApproversScreen extends StatefulWidget {
  const LeaveApproversScreen({super.key});

  @override
  State<LeaveApproversScreen> createState() => _LeaveApproversScreenState();
}

class _LeaveApproversScreenState extends State<LeaveApproversScreen> {
  bool _loading = true;
  bool _saving = false;
  Failure? _failure;
  LeaveApproverList? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final list = await getIt<EssRepository>().leaveApprovers();
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _failure = f;
        _loading = false;
      });
    }
  }

  Future<void> _choose(LeaveApproverBranch branch) async {
    final choice = await showDialog<LeaveApproverChoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Admin Manager for ${branch.name}'),
        children: [
          for (final manager in branch.adminManagers)
            ListTile(
              leading: Icon(
                manager.id == branch.selectedEmployeeId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: manager.id == branch.selectedEmployeeId
                    ? RvmColors.clay
                    : RvmColors.muted,
              ),
              title: Text(manager.fullName),
              subtitle: manager.employeeCode == null
                  ? null
                  : Text(manager.employeeCode!),
              onTap: () => Navigator.pop(dialogContext, manager),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final list = await getIt<EssRepository>().setLeaveApprover(
        branchId: branch.id,
        employeeId: choice.id,
      );
      if (!mounted) return;
      setState(() {
        _list = list;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${choice.fullName} now decides ${branch.name} leave first.',
            ),
          ),
        );
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return TeamScaffold(
      title: 'Leave approvers',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _saving ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: _body(),
    );
  }

  Widget _body() {
    final branches = _list?.branches ?? const <LeaveApproverBranch>[];
    if (_loading && _list == null) return const AppLoading();
    if (_failure != null && _list == null) {
      return AppError(message: _failure!.message, onRetry: _load);
    }
    if (branches.isEmpty) {
      return const AppEmpty(
        icon: Icons.account_tree_outlined,
        message: 'No active branches to route leave from.',
      );
    }
    return RefreshIndicator(
      color: RvmColors.clay,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          RvmSpacing.md,
          RvmSpacing.sm,
          RvmSpacing.md,
          RvmSpacing.lg,
        ),
        children: [
          Text(
            'Leave goes to the branch Admin Manager first, then to a super '
            'admin for final approval. A branch with no Admin Manager falls '
            'back to HR for the first stage.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 11,
              height: 1.45,
              color: RvmColors.muted,
            ),
          ),
          const SizedBox(height: RvmSpacing.md),
          for (final branch in branches) ...[
            _BranchCard(
              branch: branch,
              busy: _saving,
              onChoose: () => _choose(branch),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.busy,
    required this.onChoose,
  });

  final LeaveApproverBranch branch;
  final bool busy;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final manager = branch.effectiveManagerName;
    final canChoose = branch.hasSeveralAdminManagers && !busy;

    final String subtitle;
    if (branch.hasNoAdminManager) {
      subtitle =
          'No active Admin Manager. HR gives the first-stage decision (no final approval).';
    } else if (branch.hasOneAdminManager) {
      subtitle = 'The only active Admin Manager; selected automatically.';
    } else if (manager == null) {
      subtitle =
          'Several Admin Managers. Choose the one who decides this branch’s leave.';
    } else {
      subtitle = 'Chosen by a super admin.';
    }

    return TeamCard(
      onTap: canChoose ? onChoose : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  branch.name,
                  style: text.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (branch.hasNoAdminManager)
                const TeamPill(
                  label: 'HR first-stage bypass',
                  tone: TeamPillTone.warning,
                  dense: true,
                )
              else if (manager != null)
                TeamPill(
                  label: canChoose ? 'Change' : 'Selected',
                  tone: TeamPillTone.success,
                  dense: true,
                )
              else
                const TeamPill(
                  label: 'Choose',
                  tone: TeamPillTone.neutral,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: text.bodySmall?.copyWith(
              fontSize: 10.5,
              height: 1.4,
              color: RvmColors.muted,
            ),
          ),
          if (manager != null) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(
                  Icons.badge_outlined,
                  size: 14,
                  color: RvmColors.clay,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Admin Manager: $manager',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: RvmColors.teamSeed,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (branch.adminManagers.length > 1) ...[
            const SizedBox(height: 4),
            Text(
              '${branch.adminManagers.length} active Admin Managers',
              style: text.bodySmall?.copyWith(
                fontSize: 9.5,
                color: RvmColors.subtle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

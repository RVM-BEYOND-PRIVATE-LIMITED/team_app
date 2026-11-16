import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/team_auth_bloc.dart';
import '../../domain/team_stage2_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import '../stage2/stage2_shared.dart';

/// The server's answer about this phone (#52): waiting for HR, signed in
/// elsewhere, not punched in, or outside the shift. It loads `/team/access`
/// and never guesses.
class SecurityWaitScreen extends StatefulWidget {
  const SecurityWaitScreen({super.key});
  @override
  State<SecurityWaitScreen> createState() => _SecurityWaitScreenState();
}

class _SecurityWaitScreenState extends State<SecurityWaitScreen> {
  Future<TeamAccess>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().access());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('Access')),
      body: FutureBuilder<TeamAccess>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading(label: 'Checking this phone…');
          }
          if (snapshot.hasError) {
            return stage2Failure(
                snapshot.error is Failure ? snapshot.error as Failure : null,
                onRetry: _load);
          }
          final access = snapshot.data;
          if (access == null) return stage2Empty('No access answer.');
          if (access.devicePending) {
            return _WaitPanel(
              icon: Icons.phone_android,
              title: 'This phone is waiting for HR',
              message:
                  'HR has to approve this phone before the Team app opens here. '
                  'Use your old phone, or sign in again after HR approves it.',
              onCheck: _load,
              onSignOut: () => context
                  .read<TeamAuthBloc>()
                  .add(const TeamSignedOut()),
            );
          }
          if (!access.sessionLive || access.sessionSuperseded) {
            return _WaitPanel(
              icon: Icons.devices_other,
              title: 'Signed in on another phone',
              message:
                  'This sign-in ended when you signed in on another phone. '
                  'Sign in again here to use this phone.',
              onCheck: _load,
              onSignOut: () => context
                  .read<TeamAuthBloc>()
                  .add(const TeamSignedOut()),
            );
          }
          if (!access.punchedIn) {
            return _WaitPanel(
              icon: Icons.fingerprint,
              title: 'Punch in first',
              message: 'Punch in for today to use this screen.',
              onCheck: () => context.push('/me/punch').then((_) => _load()),
              actionLabel: 'Punch in',
            );
          }
          if (!access.onShift) {
            return _WaitPanel(
              icon: Icons.schedule,
              title: 'Outside your shift',
              message:
                  'This screen is open during your shift. Ask HR if the hours look wrong.',
              onCheck: _load,
            );
          }
          return _WaitPanel(
            icon: Icons.verified_user_outlined,
            title: 'You have access',
            message: 'This phone is approved and you are punched in.',
            onCheck: () => context.go('/home'),
            actionLabel: 'Open Home',
          );
        },
      ),
    );
  }
}

class _WaitPanel extends StatelessWidget {
  const _WaitPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.onCheck,
    this.onSignOut,
    this.actionLabel = 'Check again',
  });
  final IconData icon;
  final String title, message, actionLabel;
  final VoidCallback onCheck;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: p.primary),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            FilledButton.icon(
                onPressed: onCheck,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel)),
            if (onSignOut != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSignOut, child: const Text('Sign out')),
            ],
          ],
        ),
      ),
    );
  }
}

/// HR and Super Admin: the phones waiting for approval (#52 item 5).
class PhoneApprovalsScreen extends StatefulWidget {
  const PhoneApprovalsScreen({super.key});
  @override
  State<PhoneApprovalsScreen> createState() => _PhoneApprovalsScreenState();
}

class _PhoneApprovalsScreenState extends State<PhoneApprovalsScreen> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() =>
      setState(() => _future = stage2Repository().deviceRequests());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('Phones waiting')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading(label: 'Loading phones…');
          }
          if (snapshot.hasError) {
            return stage2Failure(
                snapshot.error is Failure ? snapshot.error as Failure : null,
                onRetry: _load);
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) return stage2Empty('No phone is waiting for approval.');
          return ListView.separated(
            padding: const EdgeInsets.all(RvmSpacing.md),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
            itemBuilder: (_, i) {
              final row = rows[i];
              final name = row['employee_name'] ?? row['full_name'] ?? 'Employee';
              final status = row['status']?.toString() ?? 'pending';
              return TeamCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(status,
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: status == 'pending'
                              ? () => _decide(row, approve: true)
                              : null,
                          child: const Text('Approve'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: status == 'pending'
                              ? () => _decide(row, approve: false)
                              : null,
                          child: const Text('Refuse'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _decide(Map<String, dynamic> row, {required bool approve}) async {
    final id = row['id']?.toString();
    if (id == null) return;
    String? note;
    if (!approve) {
      note = await _reason(context);
      if (note == null) return;
    }
    try {
      await stage2Repository().decideDevice(id,
          approve: approve,
          note: note,
          key: 'device-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(approve ? 'Phone approved.' : 'Phone refused.')));
        _load();
      }
    } on Failure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  Future<String?> _reason(BuildContext context) async {
    final controller = TextEditingController();
    final out = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Why refuse this phone?'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Reason')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Refuse')),
        ],
      ),
    );
    controller.dispose();
    return out != null && out.length >= 3 ? out : null;
  }
}

/// HR, CEO and Super Admin: the security alerts of the last days (#52 item 11).
class SecurityAlertsScreen extends StatefulWidget {
  const SecurityAlertsScreen({super.key});
  @override
  State<SecurityAlertsScreen> createState() => _SecurityAlertsScreenState();
}

class _SecurityAlertsScreenState extends State<SecurityAlertsScreen> {
  Future<List<TeamSecurityAlert>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() =>
      setState(() => _future = stage2Repository().securityAlerts());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('Security alerts')),
      body: FutureBuilder<List<TeamSecurityAlert>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading(label: 'Loading alerts…');
          }
          if (snapshot.hasError) {
            return stage2Failure(
                snapshot.error is Failure ? snapshot.error as Failure : null,
                onRetry: _load);
          }
          final alerts = snapshot.data ?? const [];
          if (alerts.isEmpty) return stage2Empty('No security alerts.');
          return ListView.separated(
            padding: const EdgeInsets.all(RvmSpacing.md),
            itemCount: alerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
            itemBuilder: (_, i) {
              final a = alerts[i];
              return TeamCard(
                child: Row(
                  children: [
                    Icon(
                        a.kind == 'new_phone'
                            ? Icons.phone_android
                            : a.kind == 'outside_shift'
                                ? Icons.schedule
                                : Icons.visibility_outlined,
                        color: p.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                              '${a.employeeName ?? 'Employee'}'
                              '${a.employeeCode == null ? '' : ' · ${a.employeeCode}'}'
                              ' · ${a.day}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

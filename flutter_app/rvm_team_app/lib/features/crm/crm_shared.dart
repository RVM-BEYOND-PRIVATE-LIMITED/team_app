import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/crm_repository.dart';
import '../../domain/crm_models.dart';
import '../../platform/call_launcher.dart';
import '../../widgets/blocked_state.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';

/// The CRM's repository, or null where the app's graph is not wired (a widget
/// test or a screen pumped on its own). Production always registers it.
CrmRepository? crmRepositoryOrNull() {
  final getIt = GetIt.instance;
  return getIt.isRegistered<CrmRepository>() ? getIt<CrmRepository>() : null;
}

/// The CRM repository in production. A screen built without the app's graph
/// (a widget test) asks [crmRepositoryOrNull] instead and shows a quiet error.
CrmRepository crmRepository() {
  final repository = crmRepositoryOrNull();
  if (repository == null) {
    throw StateError('The Sales CRM repository is not registered.');
  }
  return repository;
}

/// The blocked screen for a CRM refusal, or a normal error with a retry.
Widget crmFailure(
  Failure? failure, {
  required VoidCallback onRetry,
}) {
  final blocked = blockedReasonFor(failure);
  if (blocked != null) {
    return BlockedState(
      reason: blocked,
      message: failure?.message,
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
  return AppError(
    message: failure?.message ?? 'The CRM could not be loaded.',
    onRetry: onRetry,
  );
}

/// Starts a call from the app: the server opens the call and returns the
/// number once; the phone's dialer opens with it. Then the disposition form is
/// shown, even after the app is killed (the server keeps the open call).
Future<void> startCrmCall(
  BuildContext context, {
  required int leadId,
  String origin = 'dialer',
}) async {
  final repo = crmRepository();
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  try {
    final started = await repo.startCall(leadId, origin: origin);
    final number = started.phone;
    if (number == null || number.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('The call opened but the number was not returned.')));
      return;
    }
    final result = await GetIt.instance<CallLauncher>().dialNumber(number);
    if (result is CallLaunchFailure) {
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    }
    router.push('/crm/lead/$leadId/dispose?callId=${started.callId}&origin=$origin');
  } on Failure catch (failure) {
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

/// Picks up a Call started on the web: fetches the number once and opens the
/// dialer, then the form. A stale hand-off never opens the dialer.
Future<void> openWebCrmCall(
  BuildContext context, {
  required int callId,
  required int leadId,
}) async {
  final repo = crmRepository();
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  try {
    final number = await repo.dial(callId);
    final result = await GetIt.instance<CallLauncher>().dialNumber(number);
    if (result is CallLaunchFailure) {
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }
    router.pushReplacement(
        '/crm/lead/$leadId/dispose?callId=$callId&origin=callback');
  } on Failure catch (failure) {
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    router.go('/crm');
  }
}

/// One lead row: masked number only, with its stage and next follow-up.
class CrmLeadTile extends StatelessWidget {
  const CrmLeadTile({
    super.key,
    required this.lead,
    this.onTap,
    this.onCall,
  });

  final CrmLeadSummary lead;
  final VoidCallback? onTap;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final overdue = lead.overdue;
    return TeamCard(
      onTap: onTap,
      child: Row(
        children: [
          TeamAvatar(name: lead.name, size: 40),
          const SizedBox(width: RvmSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lead.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${lead.phoneMasked} · ${lead.stageName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: p.muted, fontSize: 11.5)),
                if (lead.nextFollowupAt != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Follow-up ${crmWhen(lead.nextFollowupAt!)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 10.5,
                          color: overdue ? p.danger : p.subtle,
                          fontWeight:
                              overdue ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (onCall != null)
            IconButton(
              tooltip: 'Call',
              onPressed: onCall,
              icon: Icon(Icons.call_outlined, color: p.primary),
            ),
        ],
      ),
    );
  }
}

String crmWhen(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final time = crmTime(local);
  if (day == today) return time;
  if (day == today.subtract(const Duration(days: 1))) return 'yesterday $time';
  if (day == today.add(const Duration(days: 1))) return 'tomorrow $time';
  return '${local.day}/${local.month} $time';
}

String crmTime(DateTime value) {
  final h = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final m = value.minute.toString().padLeft(2, '0');
  return '$h:$m ${value.hour < 12 ? 'AM' : 'PM'}';
}

String crmDay(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';

Future<DateTime?> pickCrmDateTime(
    BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime.now().subtract(const Duration(days: 1)),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

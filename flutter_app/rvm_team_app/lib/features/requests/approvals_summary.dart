import 'package:core_network/core_network.dart';

import '../../data/repositories/ess_repository.dart';
import '../../data/repositories/leave_repository.dart';
import '../../domain/ess_models.dart';

/// The Approvals entry's count (#45): the ESS inbox first (its client rotates
/// an expiring kept sign-in), then the Scheduler's leave queue. Either half
/// failing counts as nothing waiting there rather than hiding the entry.
Future<ApprovalsSummary> loadApprovalsSummary(
    EssRepository ess, LeaveRepository leave) async {
  var essPending = 0;
  try {
    final inbox = await ess.approvals();
    // CL/LWP are decided on the Scheduler now; the shared table means the ESS
    // inbox may still list them, so they are counted from the Scheduler only.
    essPending = inbox.requests
        .where((r) => !(r.isLeave && (r.type == 'cl' || r.type == 'lwp')))
        .length;
  } on Failure {
    // Not an ESS approver, or the ESS is down: no attendance count.
  }
  final overview = (await leave.overviewSafe()).data;
  return ApprovalsSummary(
    pending: essPending + (overview?.approvalsCount ?? 0),
    canApproveLeave: overview?.canApprove ?? false,
  );
}

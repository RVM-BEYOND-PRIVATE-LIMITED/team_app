import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/accounts_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Staff accounts / finance (Scheduler). Connectivity-guarded pass-throughs —
/// the admissions ledger, account detail, receipt, adjustment queue, and the
/// approve / reject / record-payment / adjustment / remarks writes.
class AccountsRepository with ConnectivityGuard {
  AccountsRepository({required AccountsRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final AccountsRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<AccountAdmission>> admissions({String status = 'Approved', String? search, String? locationId}) async {
    await ensureOnline();
    return _remote.admissions(status: status, search: search, locationId: locationId);
  }

  Future<AccountDetails> details(String admissionId) async {
    await ensureOnline();
    return _remote.details(admissionId);
  }

  Future<void> approve(String admissionId, AdmissionApproval approval) async {
    await ensureOnline();
    return _remote.approve(admissionId, approval);
  }

  Future<void> reject({required String admissionId, required String reason}) async {
    await ensureOnline();
    return _remote.reject(admissionId: admissionId, reason: reason);
  }

  Future<void> recordPayment(PaymentDraft draft) async {
    await ensureOnline();
    return _remote.recordPayment(draft);
  }

  Future<ReceiptData> receipt(String paymentId) async {
    await ensureOnline();
    return _remote.receipt(paymentId);
  }

  Future<void> requestAdjustment({required String paymentId, required num amount, required String reason}) async {
    await ensureOnline();
    return _remote.requestAdjustment(paymentId: paymentId, amount: amount, reason: reason);
  }

  Future<void> updateRemarks({required String admissionId, required String remarks}) async {
    await ensureOnline();
    return _remote.updateRemarks(admissionId: admissionId, remarks: remarks);
  }

  Future<List<PaymentAdjustment>> adjustments({String status = 'pending'}) async {
    await ensureOnline();
    return _remote.adjustments(status: status);
  }

  Future<void> approveAdjustment({required String adjustmentId, String? reviewNote}) async {
    await ensureOnline();
    return _remote.approveAdjustment(adjustmentId: adjustmentId, reviewNote: reviewNote);
  }

  Future<void> rejectAdjustment({required String adjustmentId, String? reviewNote}) async {
    await ensureOnline();
    return _remote.rejectAdjustment(adjustmentId: adjustmentId, reviewNote: reviewNote);
  }
}

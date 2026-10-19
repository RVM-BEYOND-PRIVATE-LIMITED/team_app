import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler accounts (finance) over the Bearer-JWT Dio. Reads auto-scope to the
/// caller's branch. Writes are gated server-side by denyWrite (accounts_admin is
/// read-only) and the adjustments queue is super-admin only.
///
/// NOT wired: POST /accounts/admissions/:id/upload-docs (multipart) — the staff
/// app has no file picker yet and the multipart field name needs confirming; it
/// lands with a dedicated document-upload pass.
class AccountsRemoteDataSource with DioExecutor {
  AccountsRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /accounts/admissions?status=&search= — approvals + ledger overview.
  Future<List<AccountAdmission>> admissions({String status = 'Approved', String? search, String? locationId}) =>
      guard(() async => Parse.accountAdmissions((await _dio.get('/accounts/admissions', queryParameters: {
            'status': status,
            if (search != null && search.isNotEmpty) 'search': search,
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// GET /accounts/admissions/:id — full detail (installments + payments).
  Future<AccountDetails> details(String admissionId) =>
      guard(() async => Parse.accountDetails((await _dio.get('/accounts/admissions/$admissionId')).data));

  /// PATCH /accounts/admissions/:id/approve.
  Future<void> approve(String admissionId, AdmissionApproval approval) => guard(() async {
        await _dio.patch('/accounts/admissions/$admissionId/approve', data: approval.toJson());
      });

  /// PATCH /accounts/admissions/:id/reject.
  Future<void> reject({required String admissionId, required String reason}) => guard(() async {
        await _dio.patch('/accounts/admissions/$admissionId/reject', data: {'rejection_reason': reason});
      });

  /// POST /accounts/payments — record a payment.
  Future<void> recordPayment(PaymentDraft draft) => guard(() async {
        await _dio.post('/accounts/payments', data: draft.toJson());
      });

  /// GET /accounts/payments/:id/receipt.
  Future<ReceiptData> receipt(String paymentId) =>
      guard(() async => Parse.receiptData((await _dio.get('/accounts/payments/$paymentId/receipt')).data));

  /// POST /accounts/payments/:id/adjustment — request a negative correction.
  Future<void> requestAdjustment({required String paymentId, required num amount, required String reason}) =>
      guard(() async {
        await _dio.post('/accounts/payments/$paymentId/adjustment',
            data: {'adjustment_amount': amount, 'reason': reason});
      });

  /// PATCH /accounts/admissions/:id/remarks.
  Future<void> updateRemarks({required String admissionId, required String remarks}) => guard(() async {
        await _dio.patch('/accounts/admissions/$admissionId/remarks', data: {'remarks': remarks});
      });

  /// GET /accounts/adjustments?status= — super-admin adjustment queue.
  Future<List<PaymentAdjustment>> adjustments({String status = 'pending'}) => guard(() async =>
      Parse.paymentAdjustments((await _dio.get('/accounts/adjustments', queryParameters: {'status': status})).data));

  /// PATCH /accounts/adjustments/:id/approve — super-admin.
  Future<void> approveAdjustment({required String adjustmentId, String? reviewNote}) => guard(() async {
        await _dio.patch('/accounts/adjustments/$adjustmentId/approve',
            data: {if (reviewNote != null) 'review_note': reviewNote});
      });

  /// PATCH /accounts/adjustments/:id/reject — super-admin.
  Future<void> rejectAdjustment({required String adjustmentId, String? reviewNote}) => guard(() async {
        await _dio.patch('/accounts/adjustments/$adjustmentId/reject',
            data: {if (reviewNote != null) 'review_note': reviewNote});
      });
}

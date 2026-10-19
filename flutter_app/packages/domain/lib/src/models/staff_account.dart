import 'staff_admission.dart' show AdmissionInstallment;

/// Scheduler accounts (finance) domain — the admissions-for-accounts list row,
/// the full account detail (installments + payments + documents), a payment, a
/// payment adjustment request, and the receipt payload.

/// One row in the accounts admissions list (approvals + ledger overview).
class AccountAdmission {
  const AccountAdmission({
    required this.id,
    required this.name,
    this.admissionNumber,
    this.phoneNumber,
    this.admissionDate,
    this.totalPayable,
    this.totalPaid,
    this.balance,
    this.approvalStatus,
    this.status,
    this.coursesStr,
    this.certificateName,
    this.batchName,
  });

  final String id;
  final String name;
  final String? admissionNumber;
  final String? phoneNumber;
  final DateTime? admissionDate;
  final num? totalPayable;
  final num? totalPaid;
  final num? balance;
  final String? approvalStatus;
  final String? status;
  final String? coursesStr;
  final String? certificateName;
  final String? batchName;

  bool get isPending => (approvalStatus ?? '').toLowerCase() == 'pending';
  bool get isApproved => (approvalStatus ?? '').toLowerCase() == 'approved';
  bool get owesMoney => (balance ?? 0) > 0;
}

/// A recorded payment (ledger entry).
class Payment {
  const Payment({
    required this.id,
    this.amountPaid,
    this.paymentDate,
    this.method,
    this.notes,
    this.receiptNumber,
    this.collectedBy,
  });

  final String id;
  final num? amountPaid;
  final DateTime? paymentDate;
  final String? method;
  final String? notes;
  final String? receiptNumber;
  final String? collectedBy;

  /// Backend records reversals as negative amounts.
  bool get isReversal => (amountPaid ?? 0) < 0;
}

/// The full account detail for one admission.
class AccountDetails {
  const AccountDetails({
    required this.name,
    this.fatherName,
    this.phone,
    this.address,
    this.idType,
    this.idNumber,
    this.admittedBy,
    this.branch,
    this.totalFees,
    this.totalPaid,
    this.balance,
    this.remarks,
    this.installments = const [],
    this.payments = const [],
    this.courses = const [],
    this.documents = const [],
  });

  final String name;
  final String? fatherName;
  final String? phone;
  final String? address;
  final String? idType;
  final String? idNumber;
  final String? admittedBy;
  final String? branch;
  final num? totalFees;
  final num? totalPaid;
  final num? balance;
  final String? remarks;
  final List<AdmissionInstallment> installments;
  final List<Payment> payments;
  final List<String> courses;
  final List<String> documents;
}

/// A pending/reviewed payment-adjustment (negative correction) request.
class PaymentAdjustment {
  const PaymentAdjustment({
    required this.id,
    this.adjustmentAmount,
    this.reason,
    this.status,
    this.createdAt,
    this.reviewNote,
    this.payment,
    this.admissionId,
    this.studentName,
    this.studentPhone,
    this.requestedBy,
    this.reviewedBy,
  });

  final String id;
  final num? adjustmentAmount;
  final String? reason;
  final String? status;
  final DateTime? createdAt;
  final String? reviewNote;
  final Payment? payment;
  final String? admissionId;
  final String? studentName;
  final String? studentPhone;
  final String? requestedBy;
  final String? reviewedBy;

  bool get isPending => (status ?? '').toLowerCase() == 'pending';
}

/// Receipt payload for one payment (GET /accounts/payments/:id/receipt).
class ReceiptData {
  const ReceiptData({
    required this.raw,
    this.studentName,
    this.receiptNumber,
    this.amountPaid,
    this.paymentDate,
    this.method,
    this.notes,
    this.admissionNumber,
  });

  final String? studentName;
  final String? receiptNumber;
  final num? amountPaid;
  final DateTime? paymentDate;
  final String? method;
  final String? notes;
  final String? admissionNumber;

  /// The full receipt map, for any fields the print view needs beyond the above.
  final Map<String, dynamic> raw;
}

// ── Write payloads ───────────────────────────────────────────────────────────

/// POST /accounts/payments.
class PaymentDraft {
  const PaymentDraft({
    required this.admissionId,
    required this.amountPaid,
    required this.paymentDate,
    required this.method,
    this.notes,
    this.reason,
  });

  final String admissionId;
  final num amountPaid;
  final DateTime paymentDate;
  final String method;
  final String? notes;

  /// Required by the backend when [amountPaid] is negative (a reversal).
  final String? reason;

  Map<String, dynamic> toJson() => {
        'admission_id': admissionId,
        'amount_paid': amountPaid,
        'payment_date':
            '${paymentDate.year.toString().padLeft(4, '0')}-${paymentDate.month.toString().padLeft(2, '0')}-${paymentDate.day.toString().padLeft(2, '0')}',
        'method': method,
        if (notes != null) 'notes': notes,
        if (reason != null) 'reason': reason,
      };
}

/// PATCH /accounts/admissions/:id/approve.
class AdmissionApproval {
  const AdmissionApproval({
    required this.finalAmountWithGst,
    this.isGstExempt = false,
    this.gstRate,
  });

  final num finalAmountWithGst;
  final bool isGstExempt;
  final num? gstRate;

  Map<String, dynamic> toJson() => {
        'finalAmountWithGST': finalAmountWithGst,
        'is_gst_exempt': isGstExempt,
        if (gstRate != null) 'gst_rate': gstRate,
      };
}

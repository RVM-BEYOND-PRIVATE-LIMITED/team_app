import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements AccountsRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Accounts parsers', () {
    test('accountAdmissions read balance + approval status', () {
      final list = Parse.accountAdmissions([
        {
          'id': 'a1',
          'admission_number': 'ADM-1',
          'name': 'Asha',
          'total_payable_amount': 50000,
          'total_paid': 20000,
          'balance': 30000,
          'approval_status': 'Pending',
          'batch_name': 'Morning Java',
          'phone_number': '9',
        },
      ]);
      final r = list.single;
      expect(r.id, 'a1');
      expect(r.balance, 30000);
      expect(r.isPending, isTrue);
      expect(r.owesMoney, isTrue);
    });

    test('accountDetails reads installments (amount) + payments (collected_by)', () {
      final d = Parse.accountDetails({
        'name': 'Asha',
        'total_fees': 50000,
        'total_paid': 20000,
        'balance': 30000,
        'installments': [
          {'id': 'i1', 'due_date': '2026-05-01', 'amount': 25000, 'status': 'Paid'},
          {'id': 'i2', 'due_date': '2026-06-01', 'amount': 25000, 'status': 'Pending'},
        ],
        'payments': [
          {'id': 'p1', 'amount_paid': 20000, 'payment_date': '2026-05-01', 'method': 'UPI', 'collected_by': 'ravi'},
        ],
        'courses': ['Java', 'Python'],
        'documents': ['http://x/id.jpg'],
        'remarks': 'ok',
      });
      expect(d.totalFees, 50000);
      expect(d.installments.first.amount, 25000);
      expect(d.payments.single.collectedBy, 'ravi');
      expect(d.courses, ['Java', 'Python']);
      expect(d.documents.single, 'http://x/id.jpg');
    });

    test('paymentAdjustments read nested payment + student', () {
      final list = Parse.paymentAdjustments([
        {
          'id': 'adj1',
          'adjustment_amount': -500,
          'reason': 'Overcharge',
          'status': 'pending',
          'payment': {'id': 'p1', 'amount_paid': 2000, 'method': 'Cash'},
          'admission_id': 'a1',
          'student_name': 'Asha',
          'requested_by': 'ravi',
        },
      ]);
      final a = list.single;
      expect(a.adjustmentAmount, -500);
      expect(a.isPending, isTrue);
      expect(a.payment!.amountPaid, 2000);
      expect(a.studentName, 'Asha');
    });

    test('receiptData reads payment_method (not method) + id_card_no + raw map', () {
      final r = Parse.receiptData({
        'receipt_number': 'RCPT-9',
        'amount_paid': 1500,
        'payment_method': 'UPI', // controller key is payment_method
        'student_name': 'Asha',
        'id_card_no': 'ADM-1',
        'notes': 'advance',
        'gst_summary': {'rate': 18},
      });
      expect(r.receiptNumber, 'RCPT-9');
      expect(r.amountPaid, 1500);
      expect(r.method, 'UPI');
      expect(r.studentName, 'Asha');
      expect(r.admissionNumber, 'ADM-1');
      expect(r.notes, 'advance');
      expect(r.raw['gst_summary'], {'rate': 18}); // raw preserved for the print view
    });
  });

  group('Write payload toJson', () {
    test('PaymentDraft emits snake_case + YYYY-MM-DD date', () {
      final j = PaymentDraft(
        admissionId: 'a1',
        amountPaid: 1500,
        paymentDate: DateTime(2026, 5, 9),
        method: 'UPI',
      ).toJson();
      expect(j['admission_id'], 'a1');
      expect(j['amount_paid'], 1500);
      expect(j['payment_date'], '2026-05-09');
      expect(j['method'], 'UPI');
    });

    test('AdmissionApproval emits finalAmountWithGST + is_gst_exempt', () {
      final j = const AdmissionApproval(finalAmountWithGst: 59000, isGstExempt: true).toJson();
      expect(j['finalAmountWithGST'], 59000);
      expect(j['is_gst_exempt'], true);
    });
  });

  group('AccountsRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late AccountsRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = AccountsRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('admissions forwards status + search', () async {
      when(() => ds.admissions(
            status: any(named: 'status'),
            search: any(named: 'search'),
            locationId: any(named: 'locationId'),
          )).thenAnswer((_) async => const []);
      await repo.admissions(status: 'Pending', search: 'asha');
      verify(() => ds.admissions(status: 'Pending', search: 'asha', locationId: null)).called(1);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.adjustments(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.adjustments(status: any(named: 'status')));
    });
  });
}

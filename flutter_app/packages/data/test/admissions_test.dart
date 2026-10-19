import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements AdmissionsRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Admissions parsers', () {
    test('admissionsPage reads metrics + rows; row id falls back to admission_id', () {
      final page = Parse.admissionsPage({
        'metrics': {
          'totalAdmissions': 12,
          'admissionsThisMonth': 3,
          'totalCollected': 500000,
          'revenueCollectedThisMonth': 100000,
          'totalOutstanding': 250000,
          'overdueCount': 2,
        },
        'admissions': [
          {
            'admission_id': 'a1',
            'student_name': 'Asha',
            'admission_number': 'ADM-1',
            'student_phone_number': '9',
            'status': 'Pending',
            'undertaking_status': 'Completed',
            'total_paid': 20000,
            'effective_remaining_due': 5000,
          },
        ],
      });
      expect(page.metrics.totalAdmissions, 12);
      expect(page.metrics.totalOutstanding, 250000);
      final r = page.admissions.single;
      expect(r.id, 'a1'); // from admission_id
      expect(r.undertakingDone, isTrue);
      expect(r.owesMoney, isTrue);
    });

    test('admissionDetail reads courses + installments', () {
      final d = Parse.admissionDetail({
        'id': 'a1',
        'student_name': 'Asha',
        'courses': [
          {'id': 'c1', 'name': 'Java'},
          {'id': 'c2', 'name': 'Python'},
        ],
        // v_installment_status columns: amount_due, due_date, status.
        'installments': [
          {'amount_due': 10000, 'due_date': '2026-05-01', 'status': 'Paid'},
          {'amount_due': 12000, 'due_date': '2026-06-01', 'status': 'Pending'},
        ],
      });
      expect(d.row.id, 'a1');
      expect(d.courses.map((c) => c.name), ['Java', 'Python']);
      // Label is synthesised from order; amount reads amount_due.
      expect(d.installments.first.label, 'Installment 1');
      expect(d.installments.first.amount, 10000);
      expect(d.installments.last.dueDate, DateTime(2026, 6, 1));
    });

    test('admissionPhoneCheck: ADMISSION vs INTAKE', () {
      final exists = Parse.admissionPhoneCheck(
          {'mode': 'ADMISSION', 'admission_id': 'a1', 'undertaking_completed': true});
      expect(exists.exists, isTrue);
      expect(exists.admissionId, 'a1');
      expect(exists.undertakingCompleted, isTrue);

      final intake = Parse.admissionPhoneCheck({'mode': 'INTAKE'});
      expect(intake.exists, isFalse);
      expect(intake.admissionId, isNull);
    });

    test('dropoutRegistry unwraps {admissions:[...]}', () {
      final rows = Parse.dropoutRegistry({
        'success': true,
        'admissions': [
          {'id': 'a1', 'student_name': 'Ravi', 'is_dropout': true, 'dropout_reason': 'Moved'},
        ],
      });
      expect(rows.single.isDropout, isTrue);
      expect(rows.single.dropoutReason, 'Moved');
    });
  });

  group('AdmissionsRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late AdmissionsRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = AdmissionsRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('list forwards search', () async {
      when(() => ds.list(search: any(named: 'search'), locationId: any(named: 'locationId')))
          .thenAnswer((_) async => const AdmissionsPage(metrics: AdmissionMetrics(), admissions: []));
      await repo.list(search: 'asha');
      verify(() => ds.list(search: 'asha', locationId: null)).called(1);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.reactivate('a1'), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.reactivate(any()));
    });

    test('markDropout forwards id + reason', () async {
      when(() => ds.markDropout(id: any(named: 'id'), reason: any(named: 'reason')))
          .thenAnswer((_) async {});
      await repo.markDropout(id: 'a1', reason: 'Moved city');
      verify(() => ds.markDropout(id: 'a1', reason: 'Moved city')).called(1);
    });
  });
}

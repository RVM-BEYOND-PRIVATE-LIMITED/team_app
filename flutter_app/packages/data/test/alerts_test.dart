import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements AlertsRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Alerts parser', () {
    test('pendingAlerts reads alerts[] with nested student + batch, keeps raw date', () {
      final list = Parse.pendingAlerts({
        'total_pending': 1,
        'alerts': [
          {
            'id': 'a1',
            'alert_type': 'absent_remarks_missing',
            'date': '2026-07-02',
            'batch_id': 'b1',
            'student_id': 's1',
            'escalated': true,
            'student': {'id': 's1', 'name': 'Asha', 'admission_number': 'RVM123'},
            'batch': {'id': 'b1', 'name': 'Morning Java'},
          },
        ],
        'grouped': {'absent_remarks_missing': []},
      });
      final a = list.single;
      expect(a.studentName, 'Asha');
      expect(a.admissionNumber, 'RVM123');
      expect(a.batchName, 'Morning Java');
      expect(a.dateRaw, '2026-07-02');
      expect(a.date, DateTime(2026, 7, 2));
      expect(a.escalated, isTrue);
    });

    test('empty alerts → empty list', () {
      expect(Parse.pendingAlerts({'total_pending': 0, 'alerts': []}), isEmpty);
    });
  });

  group('AlertsRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late AlertsRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = AlertsRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('bulkResolve forwards the date', () async {
      when(() => ds.bulkResolve(date: any(named: 'date'), alertType: any(named: 'alertType')))
          .thenAnswer((_) async {});
      await repo.bulkResolve(date: '2026-07-02');
      verify(() => ds.bulkResolve(date: '2026-07-02', alertType: null)).called(1);
    });

    test('offline → NoConnectionFailure', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.pending(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.resolve(any()));
    });
  });
}

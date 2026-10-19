import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements CeoRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('CEO parsers', () {
    test('ceoDashboard reads overview/finance/operations + maps', () {
      final d = Parse.ceoDashboard({
        'overview': {'totalStudents': 120, 'studentsJoined': 90, 'activeBatches': 8, 'totalFaculty': 12, 'onLeaveFaculty': 2},
        'finance': {
          'revenueInPeriod': 500000,
          'predictedRevenue': 750000,
          'totalOutstandingDebt': 120000,
          'paymentMethods': {'Cash': 200000, 'UPI': 300000},
        },
        'operations': {'overdueFollowUps': 5, 'admissionStatus': {'Approved': 70, 'Pending': 20}},
      });
      expect(d.overview.totalStudents, 120);
      expect(d.finance.revenueInPeriod, 500000);
      expect(d.finance.paymentMethods['UPI'], 300000);
      expect(d.operations.admissionStatus['Approved'], 70);
    });

    test('ceoTrends reads the daily points', () {
      final list = Parse.ceoTrends([
        {'date': '2026-07-01', 'admissions': 3, 'joined': 2, 'revenue': 15000, 'ticketsOpened': 1, 'ticketsResolved': 1},
      ]);
      expect(list.single.date, '2026-07-01');
      expect(list.single.admissions, 3);
      expect(list.single.revenue, 15000);
    });

    test('ceoCollectionIntel reads scalars + comparison', () {
      final c = Parse.ceoCollectionIntel({
        'collectionRate': 82.5,
        'totalReceiptsAmount': 400000,
        'revenueGap': 90000,
        'comparison': {'prevCollectionRate': 78, 'changeAmount': 20000, 'changePct': 5.2},
      });
      expect(c.collectionRate, 82.5);
      expect(c.revenueGap, 90000);
      expect(c.changePct, 5.2);
    });

    test('ceoFacultyAttendance unwraps yesterday_snapshot', () {
      final a = Parse.ceoFacultyAttendance({
        'yesterday_snapshot': {
          'snapshot_date': '2026-07-03',
          'total_faculty': 12,
          'present_count': 10,
          'absent_count': 2,
          'attendance_pct': 83.33,
          'is_live': false,
        },
        'date': '2026-07-03',
      });
      expect(a.presentCount, 10);
      expect(a.attendancePct, 83.33);
      expect(a.date, '2026-07-03');
    });
  });

  group('CeoRepository', () {
    test('offline → NoConnectionFailure', () async {
      final conn = _MockConnectivity();
      when(() => conn.isOnline).thenAnswer((_) async => false);
      final repo = CeoRepository(remote: _MockDs(), connectivity: conn);
      await expectLater(repo.dashboard(), throwsA(isA<NoConnectionFailure>()));
    });
  });
}

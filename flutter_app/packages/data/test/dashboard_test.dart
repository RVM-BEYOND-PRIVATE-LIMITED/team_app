import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDashboardDs extends Mock implements DashboardRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Dashboard parsers', () {
    test('dashboardMetrics reads camelCase keys under {metrics:{...}}', () {
      final m = Parse.dashboardMetrics({
        'metrics': {
          'totalAdmissions': 42,
          'admissionsThisMonth': 5,
          'totalCollected': 125000,
          'totalOutstanding': 30000,
          'overdueCount': 3,
          'pendingUndertakings': 7,
        },
        'admissions': [],
      });
      expect(m.totalAdmissions, 42);
      expect(m.admissionsThisMonth, 5);
      expect(m.totalCollected, 125000);
      expect(m.totalOutstanding, 30000);
      expect(m.overdueCount, 3);
      expect(m.pendingUndertakings, 7);
    });

    test('dashboardMetrics tolerates a bare metrics map + missing keys', () {
      final m = Parse.dashboardMetrics({'totalAdmissions': 9});
      expect(m.totalAdmissions, 9);
      expect(m.overdueCount, 0); // missing → default
    });

    test('yesterdayAttendance reads {attendance:int}', () {
      expect(Parse.yesterdayAttendance({'attendance': 12}), 12);
      expect(Parse.yesterdayAttendance({}), 0);
    });
  });

  group('DashboardRepository.summary', () {
    late _MockDashboardDs ds;
    late _MockConnectivity conn;
    late DashboardRepository repo;
    setUp(() {
      ds = _MockDashboardDs();
      conn = _MockConnectivity();
      repo = DashboardRepository(remote: ds, connectivity: conn);
    });

    test('online → combines metrics + yesterday attendance', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.metrics()).thenAnswer((_) async => const DashboardMetrics(totalAdmissions: 10));
      when(() => ds.yesterdayAttendance()).thenAnswer((_) async => 8);
      final s = await repo.summary();
      expect(s.metrics.totalAdmissions, 10);
      expect(s.yesterdayAttendance, 8);
    });

    test('attendance stub failure degrades to 0 without sinking the dashboard', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.metrics()).thenAnswer((_) async => const DashboardMetrics(totalAdmissions: 4));
      when(() => ds.yesterdayAttendance()).thenThrow(const ServerFailure());
      final s = await repo.summary();
      expect(s.metrics.totalAdmissions, 4);
      expect(s.yesterdayAttendance, 0);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.summary(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.metrics());
    });
  });
}

import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDataSource extends Mock implements JobsRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  late _MockDataSource ds;
  late _MockConnectivity conn;
  late JobsRepository repo;

  const job = JobSummary(id: 'j1', title: 'CAD Designer', jobType: JobType.fullTime);

  setUp(() {
    ds = _MockDataSource();
    conn = _MockConnectivity();
    repo = JobsRepository(remote: ds, connectivity: conn);
  });

  group('JobsRepository.browse', () {
    test('offline → NoConnectionFailure, data source not touched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.browse(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.browse(page: any(named: 'page')));
    });

    test('online → returns jobs from the data source', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.browse(page: any(named: 'page'))).thenAnswer((_) async => [job]);
      expect(await repo.browse(), [job]);
    });

    test('server failure from the data source propagates unchanged', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.browse(page: any(named: 'page'))).thenThrow(const ServerFailure());
      await expectLater(repo.browse(), throwsA(isA<ServerFailure>()));
    });
  });

  group('JobsRepository.profile', () {
    test('online → returns profile', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.profile()).thenAnswer((_) async => const CandidateProfile(id: 'c1', fullName: 'Aarav'));
      final p = await repo.profile();
      expect(p.fullName, 'Aarav');
    });

    test('offline → NoConnectionFailure', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.profile(), throwsA(isA<NoConnectionFailure>()));
    });
  });
}

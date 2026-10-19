import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockSupportDs extends Mock implements SupportRemoteDataSource {}

class _MockPublicDs extends Mock implements PublicRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  late _MockConnectivity conn;

  setUp(() => conn = _MockConnectivity());

  group('SupportRepository', () {
    late _MockSupportDs ds;
    late SupportRepository repo;
    setUp(() {
      ds = _MockSupportDs();
      repo = SupportRepository(remote: ds, connectivity: conn);
    });

    test('online → returns tickets', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.tickets()).thenAnswer(
          (_) async => const [SupportTicket(id: 't1', subject: 'X', status: TicketStatus.open)]);
      expect((await repo.tickets()).single.id, 't1');
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.tickets(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.tickets());
    });
  });

  group('PublicRepository', () {
    late _MockPublicDs ds;
    late PublicRepository repo;
    setUp(() {
      ds = _MockPublicDs();
      repo = PublicRepository(remote: ds, connectivity: conn);
    });

    test('online → returns companies', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.companies(page: any(named: 'page')))
          .thenAnswer((_) async => const [Company(id: 'c1', name: 'Acme')]);
      expect((await repo.companies()).single.name, 'Acme');
    });

    test('offline → NoConnectionFailure', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.companies(), throwsA(isA<NoConnectionFailure>()));
    });
  });
}

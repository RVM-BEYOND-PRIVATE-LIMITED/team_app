import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements CertificatesRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _FakeDraft extends Fake implements CertificateDraft {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeDraft()));

  group('Certificate parser', () {
    test('certificates reads a bare list', () {
      final list = Parse.certificates([
        {'id': 1, 'name': 'Diploma', 'cost': 5000},
        {'id': 2, 'name': 'Advanced', 'cost': 7500.5},
      ]);
      expect(list.first.id, '1');
      expect(list.first.name, 'Diploma');
      expect(list.first.cost, 5000);
      expect(list.last.cost, 7500.5);
    });

    test('certificateOf unwraps the {certificate:{...}} create/update envelope', () {
      final c = Parse.certificateOf({
        'message': 'Certificate created successfully',
        'certificate': {'id': 9, 'name': 'New', 'cost': 100},
      });
      expect(c.id, '9');
      expect(c.name, 'New');
      expect(c.cost, 100);
    });

    test('certificateOf reads a bare row (GET /:id)', () {
      final c = Parse.certificateOf({'id': 3, 'name': 'Solo', 'cost': 0});
      expect(c.id, '3');
      expect(c.cost, 0);
    });
  });

  group('CertificateDraft toJson', () {
    test('sends name + cost', () {
      expect(const CertificateDraft(name: 'X', cost: 250).toJson(), {'name': 'X', 'cost': 250});
    });
  });

  group('CertificatesRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late CertificatesRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = CertificatesRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('update forwards id + draft', () async {
      when(() => ds.update(any(), any()))
          .thenAnswer((_) async => const Certificate(id: '1', name: 'X', cost: 1));
      await repo.update('1', const CertificateDraft(name: 'X', cost: 1));
      verify(() => ds.update('1', any())).called(1);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.list(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.list());
    });
  });
}

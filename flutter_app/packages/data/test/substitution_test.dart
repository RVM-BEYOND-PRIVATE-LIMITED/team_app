import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements SubstitutionRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _FakeDraft extends Fake implements SubstitutionDraft {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeDraft()));

  group('Substitution parser', () {
    test('substitutions read flattened batch + nested faculty refs', () {
      final list = Parse.substitutions([
        {
          'id': 's1',
          'start_date': '2026-07-01',
          'end_date': '2026-07-05',
          'notes': 'Sick leave cover',
          'original_faculty': {'id': 'f1', 'name': 'Neha'},
          'substitute_faculty': {'id': 'f2', 'name': 'Ravi'},
          'batch_name': 'Morning Java',
          'batch_id': 'b1',
        },
      ]);
      final s = list.single;
      expect(s.batchName, 'Morning Java');
      expect(s.batchId, 'b1');
      expect(s.originalFaculty!.name, 'Neha');
      expect(s.substituteFaculty!.id, 'f2');
      expect(s.startDate, DateTime(2026, 7, 1));
    });
  });

  group('Write payload toJson', () {
    test('SubstitutionDraft emits camelCase + YYYY-MM-DD', () {
      final j = SubstitutionDraft(
        batchId: 'b1',
        substituteFacultyId: 'f2',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 5),
        notes: 'cover',
      ).toJson();
      expect(j['batchId'], 'b1');
      expect(j['substituteFacultyId'], 'f2');
      expect(j['startDate'], '2026-07-01');
      expect(j['endDate'], '2026-07-05');
      expect(j['notes'], 'cover');
    });
  });

  group('SubstitutionRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late SubstitutionRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = SubstitutionRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('assign forwards batchId + facultyId', () async {
      when(() => ds.assign(batchId: any(named: 'batchId'), facultyId: any(named: 'facultyId')))
          .thenAnswer((_) async {});
      await repo.assign(batchId: 'b1', facultyId: 'f2');
      verify(() => ds.assign(batchId: 'b1', facultyId: 'f2')).called(1);
    });

    test('merge forwards source + target', () async {
      when(() => ds.merge(sourceBatchId: any(named: 'sourceBatchId'), targetBatchId: any(named: 'targetBatchId')))
          .thenAnswer((_) async {});
      await repo.merge(sourceBatchId: 'b1', targetBatchId: 'b2');
      verify(() => ds.merge(sourceBatchId: 'b1', targetBatchId: 'b2')).called(1);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.list(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.list(locationId: any(named: 'locationId')));
    });
  });
}

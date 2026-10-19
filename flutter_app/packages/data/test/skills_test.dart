import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements SkillsRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _FakeDraft extends Fake implements SkillDraft {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeDraft()));

  group('Skill parser', () {
    test('reads name/category/description/location', () {
      final list = Parse.skills([
        {'id': 's1', 'name': 'Flutter', 'category': 'Mobile', 'description': 'UI toolkit', 'location_id': 3},
      ]);
      final s = list.single;
      expect(s.name, 'Flutter');
      expect(s.category, 'Mobile');
      expect(s.description, 'UI toolkit');
      expect(s.locationId, 3);
    });

    test('skillOf reads the bare create/update row', () {
      final s = Parse.skillOf({'id': 's9', 'name': 'Go', 'category': 'Backend'});
      expect(s.id, 's9');
      expect(s.description, isNull);
    });
  });

  group('SkillDraft toJson', () {
    test('always includes description (null clears it server-side)', () {
      expect(const SkillDraft(name: 'X', category: 'C').toJson(),
          {'name': 'X', 'category': 'C', 'description': null});
      expect(const SkillDraft(name: 'X', category: 'C', description: 'd').toJson()['description'], 'd');
    });
  });

  group('SkillsRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late SkillsRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = SkillsRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('update forwards id + draft', () async {
      when(() => ds.update(any(), any())).thenAnswer((_) async => const Skill(id: 's1', name: 'X'));
      await repo.update('s1', const SkillDraft(name: 'X', category: 'C'));
      verify(() => ds.update('s1', any())).called(1);
    });

    test('offline → NoConnectionFailure', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.list(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.list());
    });
  });
}

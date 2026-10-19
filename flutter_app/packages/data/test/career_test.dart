import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockCareerDs extends Mock implements CareerRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  setUpAll(() => registerFallbackValue(const ExperienceDraft(jobDomain: 'x')));

  group('Career parsers', () {
    test('experienceStack reads {experience_stack:[...]} and maps fields', () {
      final list = Parse.experienceStack({
        'experience_stack': [
          {
            'id': 'e1',
            'job_domain': 'CAD Design',
            'company_name': 'Lumen',
            'industry': 'Aerospace',
            'job_role': 'Designer',
            'skills': ['AutoCAD', 'GD&T'],
            'duration_months': 14,
            'is_current': true,
            'source': 'manual_experience',
            'created_at': '2026-01-02',
          }
        ],
      });
      expect(list, hasLength(1));
      final e = list.single;
      expect(e.id, 'e1');
      expect(e.jobDomain, 'CAD Design');
      expect(e.skills, ['AutoCAD', 'GD&T']);
      expect(e.durationMonths, 14);
      expect(e.isCurrent, isTrue);
      expect(e.isReadOnly, isFalse);
      expect(e.title, 'Designer · Lumen');
    });

    test('experienceEntryOf unwraps {entry:{...}} from write endpoints', () {
      final e = Parse.experienceEntryOf({
        'entry': {'id': 'e9', 'job_domain': 'Welding', 'source': 'rvm_verified_training'}
      });
      expect(e.id, 'e9');
      expect(e.jobDomain, 'Welding');
      expect(e.isReadOnly, isTrue); // RVM training → read-only in UI
      expect(e.title, 'Welding'); // falls back to domain with no role/company
    });

    test('skillSuggestions reads {suggestions:[...]} and drops nameless rows', () {
      final s = Parse.skillSuggestions({
        'suggestions': [
          {'id': 's1', 'name': 'AutoCAD', 'category': 'cad', 'usage_count': 42},
          {'id': 's2', 'name': '', 'category': 'cad'},
        ],
      });
      expect(s, hasLength(1));
      expect(s.single.name, 'AutoCAD');
      expect(s.single.usageCount, 42);
    });
  });

  group('CareerRepository', () {
    late _MockCareerDs ds;
    late _MockConnectivity conn;
    late CareerRepository repo;

    setUp(() {
      ds = _MockCareerDs();
      conn = _MockConnectivity();
      repo = CareerRepository(remote: ds, connectivity: conn);
    });

    test('online → returns experience stack', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.experienceStack()).thenAnswer(
          (_) async => const [ExperienceEntry(id: 'e1', jobDomain: 'CAD')]);
      expect((await repo.experienceStack()).single.id, 'e1');
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.experienceStack(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.experienceStack());
    });

    test('addExperience checks connectivity before hitting the data source', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(
        repo.addExperience(const ExperienceDraft(jobDomain: 'CAD')),
        throwsA(isA<NoConnectionFailure>()),
      );
      verifyNever(() => ds.addExperience(any()));
    });
  });
}

import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockSched extends Mock implements SchedulingRemoteDataSource {}

class _MockActs extends Mock implements ActivitiesRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _FakeQuery extends Fake implements SuggestFacultyQuery {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeQuery()));

  group('Parsers', () {
    test('activities reads action/item/type', () {
      final list = Parse.activities([
        {'action': 'Created', 'item': 'Batch A', 'type': 'batch', 'created_at': '2026-07-02T10:00:00Z'},
      ]);
      expect(list.single.action, 'Created');
      expect(list.single.item, 'Batch A');
    });

    test('freeSlots reads faculty + day time windows', () {
      final list = Parse.freeSlots([
        {
          'faculty': {'id': 'f1', 'name': 'Neha'},
          'slots': [
            {'date': '2026-07-02', 'time': ['09:00:00 - 11:00:00', '14:00:00 - 16:00:00']},
          ],
        },
      ]);
      expect(list.single.faculty.name, 'Neha');
      expect(list.single.days.single.date, '2026-07-02');
      expect(list.single.days.single.times.length, 2);
    });

    test('facultySuggestions unwrap {suggestions:[...]} with commonSlots + status', () {
      final list = Parse.facultySuggestions({
        'suggestions': [
          {
            'id': 'f1',
            'name': 'Neha',
            'status': 'available_other_times',
            'commonSlots': [
              {'start': '09:00', 'end': '12:00'},
            ],
          },
        ],
      });
      expect(list.single.name, 'Neha');
      expect(list.single.isFullyAvailable, isFalse);
      expect(list.single.commonSlots.single.start, '09:00');
    });
  });

  group('SuggestFacultyQuery toJson', () {
    test('sends camelCase + omits absent times', () {
      final j = const SuggestFacultyQuery(
        skillId: 'sk1',
        startDate: '2026-07-01',
        endDate: '2026-07-31',
        daysOfWeek: ['Monday', 'Wednesday'],
      ).toJson();
      expect(j['skillId'], 'sk1');
      expect(j['daysOfWeek'], ['Monday', 'Wednesday']);
      expect(j.containsKey('startTime'), isFalse);
    });
  });

  group('Repositories offline', () {
    late _MockConnectivity conn;
    setUp(() {
      conn = _MockConnectivity();
      when(() => conn.isOnline).thenAnswer((_) async => false);
    });

    test('scheduling.freeSlots offline → NoConnectionFailure', () async {
      final repo = SchedulingRepository(remote: _MockSched(), connectivity: conn);
      await expectLater(repo.freeSlots(startDate: 'a', endDate: 'b'), throwsA(isA<NoConnectionFailure>()));
    });

    test('activities offline → NoConnectionFailure', () async {
      final repo = ActivitiesRepository(remote: _MockActs(), connectivity: conn);
      await expectLater(repo.list(), throwsA(isA<NoConnectionFailure>()));
    });
  });
}

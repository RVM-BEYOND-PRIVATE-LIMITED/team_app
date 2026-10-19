import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements FacultyRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _FakeSlots extends Fake implements FacultyAvailability {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeSlots()));

  group('Availability parser', () {
    test('availabilitySlots reads day_of_week/start_time/end_time', () {
      final slots = Parse.availabilitySlots([
        {'id': 'a1', 'day_of_week': 'Monday', 'start_time': '09:00', 'end_time': '12:00'},
        {'id': 'a2', 'day_of_week': 'Wednesday', 'start_time': '14:00', 'end_time': '17:00'},
      ]);
      expect(slots, hasLength(2));
      expect(slots.first.dayOfWeek, 'Monday');
      expect(slots.first.startTime, '09:00');
      expect(slots.last.endTime, '17:00');
    });
  });

  group('FacultyRepository availability', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late FacultyRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = FacultyRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('setAvailability forwards facultyId + slots', () async {
      when(() => ds.setAvailability(facultyId: any(named: 'facultyId'), slots: any(named: 'slots')))
          .thenAnswer((_) async => const [FacultyAvailability(dayOfWeek: 'Monday', startTime: '09:00', endTime: '12:00')]);
      final out = await repo.setAvailability(
        facultyId: 'f1',
        slots: const [FacultyAvailability(dayOfWeek: 'Monday', startTime: '09:00', endTime: '12:00')],
      );
      expect(out.single.dayOfWeek, 'Monday');
      verify(() => ds.setAvailability(facultyId: 'f1', slots: any(named: 'slots'))).called(1);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.availability('f1'), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.availability(any()));
    });
  });
}

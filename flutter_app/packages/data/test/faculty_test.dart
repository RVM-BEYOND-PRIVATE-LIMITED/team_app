import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements FacultyRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Faculty parsers', () {
    test('faculty reads mixed camelCase leave keys + skills + availability', () {
      final f = Parse.faculty({
        'id': 'f1',
        'name': 'Neha',
        'email': 'neha@x.com',
        'phone_number': '9',
        'type': 'Full-time',
        'isActive': true,
        'location_id': 2,
        'status': 'On Leave',
        'leaveStartDate': '2026-07-01',
        'leaveEndDate': '2026-07-10',
        'leaveReason': 'Medical',
        'skills': [
          {'id': 's1', 'name': 'Java'},
          {'id': 's2', 'name': 'Python'},
        ],
        'availability': [
          {'id': 'a1', 'day_of_week': 'Monday', 'start_time': '09:00', 'end_time': '12:00'},
        ],
      });
      expect(f.employmentType, 'Full-time');
      expect(f.isActive, isTrue);
      expect(f.onLeave, isTrue);
      expect(f.leaveReason, 'Medical');
      expect(f.skills.map((s) => s.name), ['Java', 'Python']);
      expect(f.availability.single.dayOfWeek, 'Monday');
    });

    test('metric endpoints map faculty_id → count', () {
      expect(Parse.facultyActiveStudents([
        {'faculty_id': 'f1', 'active_students': 12},
      ]), {'f1': 12});
      expect(Parse.facultyStudentCounts([
        {'faculty_id': 'f1', 'total_students': 40},
      ]), {'f1': 40});
    });

    test('facultyTotalStudents reads total + ids', () {
      final t = Parse.facultyTotalStudents({'total_students': 3, 'students': ['a', 'b', 'c']});
      expect(t.total, 3);
      expect(t.studentIds, ['a', 'b', 'c']);
    });
  });

  group('FacultyUpdate.toJson', () {
    test('omits skillIds (preserves skills); sends both leave dates', () {
      final j = FacultyUpdate(
        name: 'Neha',
        isActive: false,
        leaveStartDate: DateTime(2026, 7, 1),
        leaveEndDate: DateTime(2026, 7, 10),
      ).toJson();
      expect(j['name'], 'Neha');
      expect(j['is_active'], false);
      expect(j['leave_start_date'], '2026-07-01');
      expect(j['leave_end_date'], '2026-07-10');
      expect(j.containsKey('skillIds'), isFalse); // preserved
    });

    test('cleared leave sends both dates AND reason as null (so they clear)', () {
      final j = const FacultyUpdate(name: 'Neha').toJson();
      expect(j['leave_start_date'], isNull);
      expect(j['leave_end_date'], isNull);
      // leave_reason must be PRESENT-and-null so the controller clears it,
      // not omitted (which would keep a stale reason).
      expect(j.containsKey('leave_reason'), isTrue);
      expect(j['leave_reason'], isNull);
    });
  });

  group('FacultyRepository.roster', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late FacultyRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = FacultyRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('merges active + total student metrics onto each faculty', () async {
      when(() => ds.list(locationId: any(named: 'locationId')))
          .thenAnswer((_) async => const [Faculty(id: 'f1', name: 'Neha')]);
      when(() => ds.activeStudents(locationId: any(named: 'locationId')))
          .thenAnswer((_) async => {'f1': 12});
      when(() => ds.studentCounts(locationId: any(named: 'locationId')))
          .thenAnswer((_) async => {'f1': 40});
      final list = await repo.roster();
      expect(list.single.activeStudents, 12);
      expect(list.single.totalStudents, 40);
    });

    test('metric failure degrades to null counts, roster survives', () async {
      when(() => ds.list(locationId: any(named: 'locationId')))
          .thenAnswer((_) async => const [Faculty(id: 'f1', name: 'Neha')]);
      when(() => ds.activeStudents(locationId: any(named: 'locationId'))).thenThrow(const ServerFailure());
      when(() => ds.studentCounts(locationId: any(named: 'locationId'))).thenThrow(const ServerFailure());
      final list = await repo.roster();
      expect(list.single.name, 'Neha');
      expect(list.single.activeStudents, isNull);
      expect(list.single.totalStudents, isNull);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.roster(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.list(locationId: any(named: 'locationId')));
    });
  });
}

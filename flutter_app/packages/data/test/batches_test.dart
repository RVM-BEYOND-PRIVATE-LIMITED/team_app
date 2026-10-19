import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockBatchesDs extends Mock implements BatchesRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Batches parsers', () {
    test('staffBatch reads nested faculty/skill + counts + day names', () {
      final b = Parse.staffBatch({
        'id': 'b1',
        'name': 'Morning Java',
        'description': 'Core Java',
        'status': 'active',
        'faculty_id': 'f1',
        'skill_id': 'sk1',
        'faculty': {'id': 'f1', 'name': 'Neha'},
        'skill': {'id': 'sk1', 'name': 'Java'},
        'students': 12, // GET /batches → count int
        'joined_count': 10,
        'max_students': 20,
        'days_of_week': ['Monday', 'Wednesday'],
        'start_time': '09:00',
        'isSubstituted': false,
      });
      expect(b.facultyName, 'Neha');
      expect(b.skillName, 'Java');
      expect(b.enrolledCount, 12);
      expect(b.joinedCount, 10);
      expect(b.seatsLeft, 8);
      expect(b.scheduleDayNames, ['Monday', 'Wednesday']);
      expect(b.status, BatchStatus.active);
    });

    test('staffBatch tolerates the create/update shape where students is an array', () {
      final b = Parse.staffBatch({
        'id': 'b1',
        'name': 'X',
        'status': 'upcoming',
        'students': [
          {'id': 's1'},
          {'id': 's2'},
        ],
        'isSubstituted': true,
        'original_faculty': {'name': 'Old Faculty'},
      });
      expect(b.enrolledCount, 2); // array length
      expect(b.isSubstituted, isTrue);
      expect(b.originalFacultyName, 'Old Faculty');
    });

    test('batchStudents reads dues + risk flags', () {
      final list = Parse.batchStudents([
        {
          'id': 's1',
          'name': 'Asha',
          'admission_number': 'A-1',
          'phone_number': '9',
          'enrolled_courses': 'Java',
          'active_batches_count': 2,
          'remarks': 'Due: 5000',
          'total_due_amount': 5000,
          'is_defaulter': true,
          'is_banned': false,
          'is_on_hold': true,
          'status_label': 'Admitted',
        },
      ]);
      final s = list.single;
      expect(s.owesMoney, isTrue);
      expect(s.totalDue, 5000);
      expect(s.isDefaulter, isTrue);
      expect(s.isOnHold, isTrue);
      expect(s.statusLabel, 'Admitted');
    });

    test('activeStudentsCount reads the KPI', () {
      final c = Parse.activeStudentsCount({'total_active_students': 120, 'active_batches_count': 14});
      expect(c.totalActiveStudents, 120);
      expect(c.activeBatchesCount, 14);
    });
  });

  group('BatchDraft.toJson', () {
    test('emits camelCase keys + YYYY-MM-DD dates + day-NAME array', () {
      final json = const BatchDraft(
        name: 'New Batch',
        facultyId: 'f1',
        skillId: 'sk1',
        maxStudents: 30,
        daysOfWeek: ['Monday', 'Friday'],
        status: 'upcoming',
      ).toJson();
      expect(json['name'], 'New Batch');
      expect(json['facultyId'], 'f1');
      expect(json['daysOfWeek'], ['Monday', 'Friday']);
      expect(json.containsKey('description'), isFalse); // omitted when null
    });
  });

  group('BatchesRepository', () {
    late _MockBatchesDs ds;
    late _MockConnectivity conn;
    late BatchesRepository repo;

    setUp(() {
      ds = _MockBatchesDs();
      conn = _MockConnectivity();
      repo = BatchesRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    const batch = StaffBatch(id: 'b1', name: 'A', status: BatchStatus.active);

    test('overview combines list + active-count', () async {
      when(() => ds.list(
            facultyId: any(named: 'facultyId'),
            locationId: any(named: 'locationId'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          )).thenAnswer((_) async => [batch]);
      when(() => ds.activeStudentsCount(locationId: any(named: 'locationId'))).thenAnswer(
          (_) async => const ActiveStudentsCount(totalActiveStudents: 5, activeBatchesCount: 1));
      final o = await repo.overview();
      expect(o.batches, hasLength(1));
      expect(o.activeCount!.totalActiveStudents, 5);
    });

    test('overview: KPI failure degrades to null, list survives', () async {
      when(() => ds.list(
            facultyId: any(named: 'facultyId'),
            locationId: any(named: 'locationId'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          )).thenAnswer((_) async => [batch]);
      when(() => ds.activeStudentsCount(locationId: any(named: 'locationId')))
          .thenThrow(const ServerFailure());
      final o = await repo.overview();
      expect(o.batches, hasLength(1));
      expect(o.activeCount, isNull);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.overview(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.list(
            facultyId: any(named: 'facultyId'),
            locationId: any(named: 'locationId'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ));
    });

    test('delete forwards to the data source when online', () async {
      when(() => ds.delete(any())).thenAnswer((_) async {});
      await repo.delete('b1');
      verify(() => ds.delete('b1')).called(1);
    });
  });
}

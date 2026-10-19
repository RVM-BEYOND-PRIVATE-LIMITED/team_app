import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements FollowUpsRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Follow-up parsers', () {
    test('followUpTasks reads tasks + counts', () {
      final p = Parse.followUpTasks({
        'tasks': [
          {
            'admission_id': 'a1',
            'student_name': 'Asha',
            'student_phone': '9',
            'admission_number': 'ADM-1',
            'batch_name': 'Morning Java',
            'next_task_due_date': '2026-07-04',
            'total_due_amount': 5000,
            'task_count': 2,
            'assigned_to': 'ravi',
          },
        ],
        'counts': {'today': 3, 'overdue': 5, 'upcoming': 8},
      });
      expect(p.tasks.single.studentName, 'Asha');
      expect(p.tasks.single.owesMoney, isTrue);
      expect(p.tasks.single.assignedTo, 'ravi');
      expect(p.today, 3);
      expect(p.overdue, 5);
      expect(p.upcoming, 8);
    });

    test('followUpLogs reads the aliased follow_up_details view keys', () {
      // The view aliases: id→follow_up_id, notes→follow_up_notes, type→follow_up_type.
      final logs = Parse.followUpLogs([
        {
          'follow_up_id': 'l1',
          'log_date': '2026-07-01',
          'follow_up_notes': 'Called, will pay Friday',
          'follow_up_type': 'Call',
          'staff_name': 'ravi',
        },
      ]);
      expect(logs.single.id, 'l1');
      expect(logs.single.date, DateTime(2026, 7, 1));
      expect(logs.single.notes, 'Called, will pay Friday');
      expect(logs.single.type, 'Call');
      expect(logs.single.staffName, 'ravi');
    });

    test('followUpLogs falls back to raw follow_ups keys', () {
      final logs = Parse.followUpLogs([
        {'id': 'l2', 'created_at': '2026-07-02', 'notes': 'x', 'type': 'Visit'},
      ]);
      expect(logs.single.id, 'l2');
      expect(logs.single.notes, 'x');
      expect(logs.single.type, 'Visit');
    });

    test('staffFollowUpReport reads entries + nested logs', () {
      final r = Parse.staffFollowUpReport({
        'total': 3,
        'report': [
          {
            'staff_name': 'ravi',
            'count': 2,
            'logs': [
              {'id': 'l1', 'date': '2026-07-01', 'notes': 'x', 'type': 'Call', 'student_name': 'Asha'},
            ],
          },
        ],
      });
      expect(r.total, 3);
      expect(r.entries.single.staffName, 'ravi');
      expect(r.entries.single.count, 2);
      expect(r.entries.single.logs.single.studentName, 'Asha');
    });
  });

  group('FollowUpLogDraft.toJson', () {
    test('emits admission_id + notes + lead_type + next_follow_up_date', () {
      final j = FollowUpLogDraft(
        admissionId: 'a1',
        notes: 'Spoke to parent',
        type: 'Call',
        leadType: 'hot',
        nextFollowUpDate: DateTime(2026, 7, 10),
      ).toJson();
      expect(j['admission_id'], 'a1');
      expect(j['notes'], 'Spoke to parent');
      expect(j['type'], 'Call');
      expect(j['lead_type'], 'hot');
      expect(j['next_follow_up_date'], '2026-07-10');
    });
  });

  group('FollowUpsRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late FollowUpsRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = FollowUpsRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('tasks forwards dateFilter + search', () async {
      when(() => ds.tasks(
            dateFilter: any(named: 'dateFilter'),
            searchTerm: any(named: 'searchTerm'),
            locationId: any(named: 'locationId'),
          )).thenAnswer((_) async => const FollowUpTasksPage(tasks: []));
      await repo.tasks(dateFilter: 'overdue', searchTerm: 'asha');
      verify(() => ds.tasks(dateFilter: 'overdue', searchTerm: 'asha', locationId: null)).called(1);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.tasks(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.tasks(
            dateFilter: any(named: 'dateFilter'),
            searchTerm: any(named: 'searchTerm'),
            locationId: any(named: 'locationId'),
          ));
    });
  });
}

import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockStudentsDs extends Mock implements StudentsRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Students parsers', () {
    test('studentsPage reads {students,count} + follow-up + flags', () {
      final page = Parse.studentsPage({
        'count': 42,
        'students': [
          {
            'id': 's1',
            'name': 'Asha',
            'admission_number': 'A-1',
            'phone_number': '9',
            'remarks': '09 Apr 2026',
            'total_due_amount': 5000,
            'is_on_hold': true,
            'hold_category': 'Medical',
            'is_defaulter': false,
            'has_followup_data': true,
            'follow_up': {'next_task_due_date': '2026-04-09', 'total_due': 5000, 'task_count': 1},
          },
        ],
      });
      expect(page.count, 42);
      final s = page.students.single;
      expect(s.name, 'Asha');
      expect(s.owesMoney, isTrue);
      expect(s.isOnHold, isTrue);
      expect(s.holdCategory, 'Medical');
      expect(s.nextTaskDueDate, DateTime(2026, 4, 9));
      expect(s.hasAdmissionNumber, isTrue);
    });

    test('studentsPage count falls back to list length when absent', () {
      final page = Parse.studentsPage({
        'students': [
          {'id': 's1', 'name': 'A'},
        ],
      });
      expect(page.count, 1);
    });

    test('hasAdmissionNumber false for N/A / blank', () {
      expect(Parse.staffStudentOf({'id': 's1', 'name': 'A', 'admission_number': 'N/A'}).hasAdmissionNumber,
          isFalse);
      expect(Parse.staffStudentOf({'id': 's1', 'name': 'A'}).hasAdmissionNumber, isFalse);
    });

    test('defaulterStatus reads the flag + reason', () {
      final d = Parse.defaulterStatus({'is_defaulter': true, 'reason': 'Fees', 'has_admission_no': true});
      expect(d.isDefaulter, isTrue);
      expect(d.reason, 'Fees');
      expect(d.hasAdmissionNo, isTrue);
    });

    test('studentBatchList unwraps {batches:[...]} with nested faculty', () {
      final list = Parse.studentBatchList({
        'batches': [
          {'id': 'b1', 'name': 'Java', 'faculty': {'name': 'Neha'}},
        ],
      });
      expect(list.single.name, 'Java');
      expect(list.single.facultyName, 'Neha');
    });
  });

  group('StudentDraft.toJson', () {
    test('emits snake_case keys, omits nulls', () {
      final json = const StudentDraft(name: 'Asha', admissionNumber: 'A-1').toJson();
      expect(json['name'], 'Asha');
      expect(json['admission_number'], 'A-1');
      expect(json.containsKey('phone_number'), isFalse);
    });
  });

  group('StudentsRepository', () {
    late _MockStudentsDs ds;
    late _MockConnectivity conn;
    late StudentsRepository repo;

    setUp(() {
      ds = _MockStudentsDs();
      conn = _MockConnectivity();
      repo = StudentsRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('list forwards paging + filters', () async {
      when(() => ds.list(
            search: any(named: 'search'),
            locationId: any(named: 'locationId'),
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            onHold: any(named: 'onHold'),
            feePending: any(named: 'feePending'),
          )).thenAnswer((_) async => const StudentsPage(students: [], count: 0));
      await repo.list(search: 'asha', page: 2, onHold: true);
      verify(() => ds.list(
            search: 'asha',
            locationId: null,
            page: 2,
            limit: 20,
            onHold: true,
            feePending: false,
          )).called(1);
    });

    test('offline → NoConnectionFailure before hitting the data source', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.markDefaulter(id: 's1'), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.markDefaulter(id: any(named: 'id'), reason: any(named: 'reason')));
    });

    test('hold forwards category + remarks', () async {
      when(() => ds.hold(
            id: any(named: 'id'),
            category: any(named: 'category'),
            remarks: any(named: 'remarks'),
          )).thenAnswer((_) async {});
      await repo.hold(id: 's1', category: 'Medical', remarks: 'On leave');
      verify(() => ds.hold(id: 's1', category: 'Medical', remarks: 'On leave')).called(1);
    });
  });
}

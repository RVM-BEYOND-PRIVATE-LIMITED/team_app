import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements AllotmentRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Allotment parsers', () {
    test('allotmentRows read flags + batch names + counts', () {
      final rows = Parse.allotmentRows([
        {
          'admission_id': 'a1',
          'student_name': 'Asha',
          'course_name': 'Java',
          'batch_names': ['Morning', 'Evening'],
          'joined': false,
          'red_flag_status': true,
          'red_flag_reason': 'remarks',
          'total_joining_date_changes': 4,
          'remarks_count': 9,
          'follow_up_count': 3,
        },
      ]);
      final r = rows.single;
      expect(r.batchNames, ['Morning', 'Evening']);
      expect(r.allotted, isTrue);
      expect(r.redFlag, isTrue);
      expect(r.followUpCount, 3);
    });

    test('followUpHistory reads nested user + total_count', () {
      final h = Parse.followUpHistory({
        'student_name': 'Asha',
        'total_count': 2,
        'follow_ups': [
          {'id': 'f1', 'notes': 'Called', 'status': 'Contacted', 'created_at': '2026-05-01', 'user': {'username': 'ravi'}},
          {'id': 'f2', 'notes': 'No answer', 'status': 'Pending'},
        ],
      });
      expect(h.studentName, 'Asha');
      expect(h.totalCount, 2);
      expect(h.followUps.first.byUser, 'ravi');
    });

    test('followUpOf unwraps {follow_up:{...}}', () {
      final f = Parse.followUpOf({'success': true, 'follow_up': {'id': 'f9', 'notes': 'ok'}});
      expect(f.id, 'f9');
      expect(f.notes, 'ok');
    });

    test('remarkHistory reads remark_text/created_by', () {
      final list = Parse.remarkHistory([
        {'remark_text': 'Late fee', 'created_at': '2026-05-01', 'created_by': 'admin'},
      ]);
      expect(list.single.text, 'Late fee');
      expect(list.single.createdBy, 'admin');
    });

    test('redFlagSummary reads count + students', () {
      final s = Parse.redFlagSummary({
        'total_red_flagged': 2,
        'students': [
          {'admission_id': 'a1', 'student_name': 'Asha', 'red_flag_reason': 'date_changes', 'total_joining_date_changes': 5},
        ],
      });
      expect(s.totalRedFlagged, 2);
      expect(s.students.single.totalDateChanges, 5);
    });
  });

  group('Write payload toJson', () {
    test('AllotmentUpdate emits joined + joining_date (YYYY-MM-DD)', () {
      final j = AllotmentUpdate(joined: true, joiningDate: DateTime(2026, 6, 1), remarks: 'ok').toJson();
      expect(j['joined'], true);
      expect(j['joining_date'], '2026-06-01');
      expect(j['remarks'], 'ok');
    });

    test('FollowUpDraft emits notes + status + next_follow_up_date', () {
      final j = FollowUpDraft(notes: 'Call', status: 'Pending', nextFollowUpDate: DateTime(2026, 6, 5)).toJson();
      expect(j['notes'], 'Call');
      expect(j['next_follow_up_date'], '2026-06-05');
    });
  });

  group('AllotmentRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late AllotmentRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = AllotmentRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('list forwards search', () async {
      when(() => ds.list(search: any(named: 'search'), locationId: any(named: 'locationId')))
          .thenAnswer((_) async => const []);
      await repo.list(search: 'asha');
      verify(() => ds.list(search: 'asha', locationId: null)).called(1);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.redFlagSummary(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.redFlagSummary(locationId: any(named: 'locationId')));
    });
  });
}

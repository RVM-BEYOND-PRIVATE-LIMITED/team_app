import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAttendanceDs extends Mock implements AttendanceRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Attendance parsers', () {
    test('dailyRoster reads nested student + eligibility flags', () {
      final rows = Parse.dailyRoster([
        {
          'batch_id': 'b1',
          'student_id': 's1',
          'date': '2026-07-03',
          'is_present': true,
          'is_eligible': true,
          'student': {'id': 's1', 'name': 'Asha', 'admission_number': 'A-1', 'phone_number': '9'},
        },
        {
          'student_id': 's2',
          'is_present': false,
          'not_yet_joined': true,
          'is_placeholder': true,
          'student': {'id': 's2', 'name': 'Ravi'},
        },
      ]);
      expect(rows, hasLength(2));
      expect(rows[0].studentName, 'Asha');
      expect(rows[0].admissionNumber, 'A-1');
      expect(rows[0].isPresent, isTrue);
      expect(rows[1].notYetJoined, isTrue);
      expect(rows[1].isMarkable, isFalse); // not-yet-joined can't be toggled
      // is_eligible omitted → defaults eligible so the row still shows.
      expect(rows[1].isEligible, isTrue);
    });

    test('batchHistory maps studentId → session list; drops undated rows', () {
      final map = Parse.batchHistory({
        's1': [
          {'date': '2026-07-03', 'is_present': true},
          {'date': '2026-07-02', 'is_present': false, 'absent_reason': 'Sick'},
          {'is_present': true}, // no date → dropped
        ],
      });
      expect(map['s1'], hasLength(2));
      expect(map['s1']![1].absentReason, 'Sick');
    });

    test('historyList parses a bare session array', () {
      final log = Parse.historyList([
        {'date': '2026-07-03', 'is_present': false, 'remarks_updated_by': 'Admin'},
      ]);
      expect(log.single.isPresent, isFalse);
      expect(log.single.remarksUpdatedBy, 'Admin');
    });

    test('batchPendingRemarks unwraps {records:[...]}', () {
      final list = Parse.batchPendingRemarks({
        'records': [
          {
            'id': 42,
            'student_id': 's1',
            'date': '2026-07-03',
            'absent_reason': null,
            'attendance_percentage': 80,
            'student': {'id': 's1', 'name': 'Asha', 'admission_number': 'A-1'},
          },
        ],
      });
      expect(list.single.attendanceId, '42');
      expect(list.single.attendancePercentage, 80);
      expect(list.single.hasRemark, isFalse);
    });

    test('pendingRemarksGroups reads {batches:[{students:[...]}]}', () {
      final groups = Parse.pendingRemarksGroups({
        'date': '2026-07-03',
        'total_pending': 2,
        'batches': [
          {
            'batch_id': 'b1',
            'batch_name': 'Morning Java',
            'pending_count': 2,
            'start_time': '09:00',
            'location_id': 5,
            'students': [
              {'attendance_id': 1, 'student_id': 's1', 'student_name': 'Asha', 'date': '2026-07-03'},
              {'attendance_id': 2, 'student_id': 's2', 'student_name': 'Ravi', 'date': '2026-07-03'},
            ],
          },
        ],
      });
      expect(groups.single.batchName, 'Morning Java');
      expect(groups.single.pendingCount, 2);
      expect(groups.single.students, hasLength(2));
      // Each grouped student inherits its batch id/name.
      expect(groups.single.students.first.batchId, 'b1');
      expect(groups.single.students.first.batchName, 'Morning Java');
    });

    test('todayAttendancePercentage reads the KPI (nullable)', () {
      expect(Parse.todayAttendancePercentage({'overall_attendance_percentage': 82.5}), 82.5);
      expect(Parse.todayAttendancePercentage({'overall_attendance_percentage': null}), isNull);
    });

    test('overallReport parses stringy percentages + location breakdown', () {
      final r = Parse.overallReport({
        'overall_attendance_percentage': 76.4,
        'total_expected_records': 100,
        'total_present': 76,
        'location_breakdown': [
          {'location_id': 1, 'total_expected_records': 50, 'total_present': 40, 'attendance_percentage': '80.00'},
        ],
      });
      expect(r.overallPercentage, 76.4);
      expect(r.totalPresent, 76);
      expect(r.locations.single.percentage, 80.0);
    });

    test('facultyReport reads batches + compliance sub-object', () {
      final r = Parse.facultyReport({
        'faculty_id': 'f1',
        'faculty_name': 'Neha',
        'faculty_attendance_percentage': 91.2,
        'batches': [
          {
            'batch_id': 'b1',
            'batch_name': 'Batch A',
            'status': 'active',
            'student_count': 12,
            'expected_sessions': 20,
            'marked_sessions': 18,
            'attendance_percentage': 90.0,
            'compliance': {'missing_attendance_dates': ['2026-07-01'], 'is_complete': false},
          },
        ],
        'missing_logs': [
          {'batch_name': 'Batch A', 'count': 2},
        ],
      });
      expect(r.percentage, 91.2);
      expect(r.batches.single.markedSessions, 18);
      expect(r.batches.single.missingDates, ['2026-07-01']);
      expect(r.batches.single.isComplete, isFalse);
      expect(r.missingLogs.single.count, 2);
    });

    test('complianceReport maps faculty_reports; total_sessions → markedSessions', () {
      final r = Parse.complianceReport({
        'overall_attendance_percentage': 88.0,
        'faculty_reports': [
          {
            'faculty_id': 'f1',
            'faculty_name': 'Neha',
            'location_id': 2,
            'faculty_attendance_percentage': 88.0,
            'batches': [
              {
                'batch_id': 'b1',
                'batch_name': 'Batch A',
                'student_count': 10,
                'expected_sessions': 12,
                'total_sessions': 11, // compliance uses total_sessions
                'attendance_percentage': 90.0,
              },
            ],
            'missing_logs': [],
          },
        ],
      });
      expect(r.faculties.single.batches.single.markedSessions, 11);
      expect(r.faculties.single.percentage, 88.0);
    });

    test('batchReport reads students + compliance counts', () {
      final r = Parse.batchReport({
        'students': [
          {
            'id': 's1',
            'name': 'Asha',
            'admission_number': 'A-1',
            'remarks': 'FULL PAID',
            'total_due_amount': 0,
            'is_defaulter': false,
            'is_banned': true,
          },
        ],
        'compliance': {'expected_days_count': 20, 'marked_days_count': 18},
      });
      expect(r.students.single.remarks, 'FULL PAID');
      expect(r.students.single.isBanned, isTrue);
      expect(r.expectedDays, 20);
      expect(r.markedDays, 18);
    });
  });

  group('AttendanceRepository', () {
    late _MockAttendanceDs ds;
    late _MockConnectivity conn;
    late AttendanceRepository repo;

    final date = DateTime(2026, 7, 3);

    setUp(() {
      ds = _MockAttendanceDs();
      conn = _MockConnectivity();
      repo = AttendanceRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('today combines grouped pending + KPI', () async {
      when(() => ds.pendingRemarksByBatch(date: any(named: 'date'))).thenAnswer((_) async => const [
            PendingRemarksGroup(batchId: 'b1', batchName: 'A', pendingCount: 1, students: []),
          ]);
      when(() => ds.todaySummary(locationId: any(named: 'locationId'))).thenAnswer((_) async => 82.0);
      final t = await repo.today(date: date);
      expect(t.groups, hasLength(1));
      expect(t.overallPercentage, 82.0);
      expect(t.totalPending, 1);
    });

    test('today: KPI failure degrades to null without sinking the queue', () async {
      when(() => ds.pendingRemarksByBatch(date: any(named: 'date'))).thenAnswer((_) async => const []);
      when(() => ds.todaySummary(locationId: any(named: 'locationId')))
          .thenThrow(const ServerFailure());
      final t = await repo.today(date: date);
      expect(t.groups, isEmpty);
      expect(t.overallPercentage, isNull);
    });

    test('markSheet: roster required, history/pending are non-critical', () async {
      when(() => ds.daily(batchId: any(named: 'batchId'), date: any(named: 'date')))
          .thenAnswer((_) async => const [
                AttendanceEntry(studentId: 's1', studentName: 'Asha', isPresent: false),
              ]);
      when(() => ds.batchHistory(any())).thenThrow(const ServerFailure());
      when(() => ds.batchPendingRemarks(any())).thenThrow(const ServerFailure());
      final sheet = await repo.markSheet(batchId: 'b1', date: date);
      expect(sheet.entries, hasLength(1));
      expect(sheet.historyByStudent, isEmpty);
      expect(sheet.pendingRemarks, isEmpty);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.today(date: date), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.pendingRemarksByBatch(date: any(named: 'date')));
    });

    test('save passes marks through when online', () async {
      when(() => ds.save(
            batchId: any(named: 'batchId'),
            date: any(named: 'date'),
            marks: any(named: 'marks'),
          )).thenAnswer((_) async {});
      await repo.save(batchId: 'b1', date: date, marks: const [(studentId: 's1', isPresent: true)]);
      verify(() => ds.save(batchId: 'b1', date: date, marks: any(named: 'marks'))).called(1);
    });

    test('updateRemark forwards to the data source', () async {
      when(() => ds.updateRemark(
            attendanceId: any(named: 'attendanceId'),
            absentReason: any(named: 'absentReason'),
            followUpComment: any(named: 'followUpComment'),
          )).thenAnswer((_) async {});
      await repo.updateRemark(attendanceId: '42', absentReason: 'Sick');
      verify(() => ds.updateRemark(attendanceId: '42', absentReason: 'Sick', followUpComment: null))
          .called(1);
    });
  });
}

import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/domain/team_stage2_models.dart';
import 'package:rvm_team_app/widgets/blocked_state.dart';

void main() {
  group('#52 access and idle lock', () {
    test('the lock is open one minute before the limit and shut at it', () {
      final start = DateTime(2026, 11, 16, 9);
      final lock = IdleLock(limit: const Duration(minutes: 30), lastActive: start);
      expect(lock.lockedAt(start.add(const Duration(minutes: 29))), isFalse);
      expect(lock.lockedAt(start.add(const Duration(minutes: 30))), isTrue);
      expect(lock.remainingAt(start.add(const Duration(minutes: 29))),
          const Duration(minutes: 1));
    });

    test('reads the phone, session, punch and shift facts', () {
      final access = TeamAccess.fromJson({
        'employee': {'id': 'e1', 'full_name': 'Test Employee'},
        'punched_in': true,
        'on_shift': false,
        'shift': {'start': '09:00', 'end': '18:00'},
        'device': {'status': 'pending', 'pending': true},
        'session': {'live': false, 'superseded': true},
        'idle_minutes': 30,
        'modules': [
          {'key': 'fees', 'sensitive': true}
        ],
        'now': '2026-11-16T09:00:00+05:30',
      });
      expect(access.employeeName, 'Test Employee');
      expect(access.punchedIn, isTrue);
      expect(access.onShift, isFalse);
      expect(access.devicePending, isTrue);
      expect(access.sessionSuperseded, isTrue);
      expect(access.modules, {'fees'});
    });

    test('generic gate codes use the shared blocked screen', () {
      Failure forbidden(String code) =>
          Failure.fromStatus(403, 'The server said why.', code);
      expect(blockedReasonFor(forbidden('NOT_PUNCHED_IN')),
          BlockedReason.notPunchedIn);
      expect(blockedReasonFor(forbidden('OUTSIDE_SHIFT')),
          BlockedReason.outsideShift);
      expect(blockedReasonFor(forbidden('DEVICE_APPROVAL_PENDING')),
          BlockedReason.pilotOnly);
    });
  });

  group('#53 fees and ops', () {
    test('the next follow-up is tomorrow or later, never today', () {
      final now = DateTime(2026, 11, 16, 10);
      const base = FeeOutcomeDraft(status: 'Answered', remark: 'Spoke');
      expect(base.copyWith(nextDate: DateTime(2026, 11, 16)).validate(now: now),
          'The next follow-up must be tomorrow or later.');
      expect(base.copyWith(nextDate: DateTime(2026, 11, 17)).validate(now: now),
          isNull);
    });

    test('the fees row has no money field at all', () {
      final row = FeeFollowup.tryParse({
        'admission_id': 'a1',
        'student_name': 'Test Student',
        'admission_number': 'A-1',
        'phone_masked': 'xxxxxx0001',
        'courses': 'Design',
        'batch_name': 'Morning',
        'call_due_date': '2026-11-16',
        'days_overdue': 4,
        'last_remark': 'Will pay',
        'last_outcome': 'No Answer',
        'last_contact_at': null,
        'source': 'current',
      })!;
      expect(row.daysOverdue, 4);
      expect(row.phoneMasked, 'xxxxxx0001');
      // The model's field list is the guarantee: no paise, amount or due.
      expect(row.props.toString(), isNot(contains('paise')));
      expect(row.props.toString(), isNot(contains('amount')));
    });

    test('pending counts and branch health parse the server shapes', () {
      final count = PendingCount.fromJson(
          {'key': 'fee_followups_due', 'count': 3, 'available': true, 'list': 'fees_followups'});
      expect(count.label, 'Fee follow-ups due');
      final health = BranchHealth.fromJson({
        'from': '2026-11-10',
        'to': '2026-11-16',
        'branches': [
          {
            'location_id': 1,
            'name': 'Main',
            'admissions': 4,
            'joining': {'expected': 5, 'pending': 1, 'allotted': 3, 'joined': 2},
            'attendance': {'marked': 10, 'present': 8, 'pct': 80.0},
            'dropouts': {'count': 1, 'reasons': {'fees': 1}},
            'overdue_students': {'1_30': 1, '31_60': 0, 'over_60': 0, 'total': 1},
          }
        ],
      });
      expect(health.branches.single.name, 'Main');
      expect(health.branches.single.joining?.joined, 2);
      expect(health.branches.single.attendancePct, 80);
    });
  });

  group('#55 scorecards', () {
    test('an Admin Manager card drops money even if a reply carries it', () {
      final card = Scorecard.fromJson({
        'audience': 'admin_manager',
        'period': {'kind': 'week', 'starts_on': '2026-11-16', 'ends_on': '2026-11-22'},
        'branches': [
          {
            'location_id': 1,
            'name': 'Main',
            'numbers': [
              {'key': 'attendance_pct', 'value': 91, 'unit': 'percent', 'target': 90, 'better': 'higher', 'state': 'green', 'available': true},
              {'key': 'collections_paise', 'value': 100000, 'unit': 'paise', 'target': null, 'better': 'higher', 'state': 'none', 'available': true},
            ],
          }
        ],
      });
      final safe = card.withoutMoneyForAdminManager();
      expect(safe.branches.single.numbers.map((n) => n.key), ['attendance_pct']);
      expect(safe.branches.single.numbers.first.state, 'green');
    });

    test('paise is rendered by the one formatter', () {
      expect(RvmMoney.fromPaise(100000), '₹1,000');
      expect(RvmMoney.fromPaise(123456789), '₹12,34,567.89');
    });
  });

  group('#54 social', () {
    test('an editor only gets Done on a To do card', () {
      final card = SocialCard.tryParse({
        'id': 'c1',
        'kind': 'cut',
        'title': 'Reel',
        'stage': 'todo',
        'editor': {'employee_id': 'e1', 'name': 'Editor'},
        'accounts': [],
        'brief': {},
        'created_at': '2026-11-16T09:00:00+05:30',
      })!;
      expect(card.isEditorAction, isTrue);
      expect(card.isLive, isFalse);
    });

    test('a shoot reads its cuts and tags', () {
      final shoot = SocialShoot.tryParse({
        'id': 's1',
        'card_id': 'c1',
        'title': 'Shoot',
        'day': '2026-11-18',
        'start_time': '10:00',
        'minutes': 60,
        'place': 'Lab',
        'prepare': 'Camera',
        'status': 'booked',
        'people': [
          {'employee_id': 'e1', 'name': 'Faculty One'}
        ],
        'progress': {'cuts': 9, 'live': 4},
      })!;
      expect(shoot.progressLabel, '4 of 9 cuts live');
      expect(shoot.people.single.name, 'Faculty One');
    });
  });

  group('#56 desk and placement', () {
    test('the flag and the proof come from the server', () {
      final task = PlacementVerification.tryParse({
        'id': 'proof:1',
        'student_name': 'Test Student',
        'company': 'Test Co',
        'role': 'Designer',
        'source': 'proof',
        'created_at': '2026-11-01T09:00:00+05:30',
        'age_days': 15,
        'flagged': true,
        'status': 'flagged',
        'has_proof': true,
        'student_call': null,
        'company_call': null,
      })!;
      expect(task.flagged, isTrue);
      expect(task.ageDays, 15);
      expect(task.hasProof, isTrue);
    });

    test('a desk queue keeps the server count', () {
      final q = DeskQueue.fromJson(
          {'count': 2, 'available': true}, key: 'phone_change_requests');
      expect(q.count, 2);
      expect(q.label, 'Phone change requests');
    });
  });

  group('#57 faculty', () {
    test('the roster fee hold is a yes or no, default false', () {
      final held = ClassRosterStudent.fromJson({
        'id': 's1',
        'full_name': 'Test Student',
        'fee_hold': true,
      });
      final normal = ClassRosterStudent.fromJson({'id': 's2'});
      expect(held.feeHold, isTrue);
      expect(normal.feeHold, isFalse);
    });

    test('a Meet link is only there when the server sends one', () {
      final withLink = FacultySession.fromJson({
        'id': 'b1',
        'name': 'Batch',
        'meet_link': 'https://meet.google.com/abc-defg-hij',
        'covered': false,
        'students': 3,
        'marked': false,
      });
      final without = FacultySession.fromJson(
          {'id': 'b2', 'name': 'Batch', 'covered': false, 'students': 3, 'marked': false});
      expect(withLink.meetLink, 'https://meet.google.com/abc-defg-hij');
      expect(without.meetLink, isNull);
    });

    test('marks are a number or an absent switch', () {
      const row = MarksRosterRow(
          studentId: 's1', name: 'Test', admissionNumber: 'A1');
      expect(row.copyWith(marks: 42).toJson(),
          {'student_id': 's1', 'marks': 42});
      expect(row.copyWith(absent: true).toJson(),
          {'student_id': 's1', 'absent': true});
    });
  });

  group('#58 complaints and moderation', () {
    test('the clocks and the Reopened mark come from the server', () {
      final row = ComplaintRow.tryParse({
        'id': 'c1',
        'category': 'Fees',
        'student_name': 'Test Student',
        'course': 'Design',
        'batch_name': 'Morning',
        'status': 'open',
        'created_at': '2026-11-15T09:00:00+05:30',
        'reply_due_at': '2026-11-16T09:00:00+05:30',
        'resolve_due_at': '2026-11-17T09:00:00+05:30',
        'reply_overdue': true,
        'resolve_overdue': false,
        'reopened': true,
        'queue': 'branch',
      })!;
      expect(row.overdueReply, isTrue);
      expect(row.overdueResolve, isFalse);
      expect(row.reopened, isTrue);
    });

    test('a reported post keeps its count and hidden state', () {
      final report = ModerationReport.tryParse({
        'id': 'r1',
        'post_id': 'p1',
        'post_text': 'Reported text',
        'group_name': 'Group',
        'reports': 3,
        'hidden': true,
      })!;
      expect(report.reports, 3);
      expect(report.hidden, isTrue);
    });
  });
}

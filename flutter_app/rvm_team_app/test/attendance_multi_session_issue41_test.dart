import 'package:core_auth/core_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/data/location_service.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/data/repositories/my_attendance_repository.dart';
import 'package:rvm_team_app/domain/attendance_models.dart';
import 'package:rvm_team_app/features/attendance/bloc/punch_bloc.dart';

/// Issue #41: a day allows several in/out sessions. The Scheduler backend no
/// longer closes the day after one Punch Out; it sends `done: false` and the
/// three-minute wait as `cooldown_seconds` / `next_punch_at`.
class _MockAttendanceRepository extends Mock
    implements MyAttendanceRepository {}

class _MockEssRepository extends Mock implements EssRepository {}

class _MockAuthSession extends Mock implements AuthSession {}

const _fix = LocationFix(
  latitude: 12.9716,
  longitude: 77.5946,
  accuracyM: 5,
  mocked: false,
);

PunchToday _secondSession() => PunchToday(
      day: '2026-10-30',
      punchedIn: true,
      done: false,
      firstIn: DateTime.utc(2026, 10, 30, 4, 0),
      punches: [
        AttendancePunch(kind: 'in', at: DateTime.utc(2026, 10, 30, 4, 0)),
        AttendancePunch(kind: 'out', at: DateTime.utc(2026, 10, 30, 4, 4)),
        AttendancePunch(kind: 'in', at: DateTime.utc(2026, 10, 30, 4, 8)),
      ],
      workedMinutes: 4,
      cooldownSeconds: 180,
      nextPunchAt: DateTime.utc(2026, 10, 30, 4, 11),
    );

void main() {
  late _MockAttendanceRepository repo;
  late PunchBloc bloc;

  setUp(() {
    repo = _MockAttendanceRepository();
    bloc = PunchBloc(repo, _MockEssRepository(), _MockAuthSession());
  });

  tearDown(() => bloc.close());

  test('the server counts a second session, not a closed day', () {
    final today = PunchToday.fromJson({
      'day': '2026-10-30',
      'punched_in': true,
      'done': false,
      'first_in': '2026-10-30T04:00:00Z',
      'punches': [
        {'kind': 'in', 'at': '2026-10-30T04:00:00Z'},
        {'kind': 'out', 'at': '2026-10-30T04:04:00Z'},
        {'kind': 'in', 'at': '2026-10-30T04:08:00Z'},
      ],
      'worked_minutes': 4,
      'cooldown_seconds': 180,
      'next_punch_at': '2026-10-30T04:11:00Z',
    });

    expect(today.done, isFalse);
    expect(today.punchedIn, isTrue);
    expect(today.punches.map((p) => p.kind), ['in', 'out', 'in']);
    expect(today.cooldownSeconds, 180);
    expect(today.nextPunchAt, DateTime.utc(2026, 10, 30, 4, 11));
  });

  test('a second Punch In is accepted and the resynced card shows the next wait',
      () async {
    when(() => repo.fix()).thenAnswer((_) async => _fix);
    when(() => repo.punch(kind: 'in', fix: _fix)).thenAnswer(
      (_) async => PunchAccepted(
        kind: 'in',
        at: DateTime.utc(2026, 10, 30, 4, 8),
      ),
    );
    when(() => repo.myAttendance()).thenAnswer(
      (_) async => MyAttendance(linked: true, today: _secondSession()),
    );

    final accepted = bloc.stream.firstWhere((s) => s.lastPunch != null);
    bloc.add(const PunchRequested('in'));
    final state = await accepted;

    expect(state.punching, isFalse);
    expect(state.data?.today?.punchedIn, isTrue);
    expect(state.data?.today?.done, isFalse);
    expect(state.data?.today?.cooldownSeconds, 180);
    verify(() => repo.punch(kind: 'in', fix: _fix)).called(1);
  });
}

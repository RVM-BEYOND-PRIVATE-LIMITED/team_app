import 'package:core_auth/core_auth.dart';
import 'package:core_network/core_network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/data/location_service.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/data/repositories/my_attendance_repository.dart';
import 'package:rvm_team_app/domain/attendance_models.dart';
import 'package:rvm_team_app/features/attendance/bloc/punch_bloc.dart';

class _MockAttendanceRepository extends Mock
    implements MyAttendanceRepository {}

class _MockEssRepository extends Mock implements EssRepository {}

class _MockAuthSession extends Mock implements AuthSession {}

const _today = MyAttendance(linked: true);

const _fix = LocationFix(
  latitude: 12.9716,
  longitude: 77.5946,
  accuracyM: 5,
  mocked: false,
);

void main() {
  late _MockAttendanceRepository repo;
  late PunchBloc bloc;

  setUp(() {
    repo = _MockAttendanceRepository();
    bloc = PunchBloc(repo, _MockEssRepository(), _MockAuthSession());
  });

  tearDown(() => bloc.close());

  test(
    'a 409 cooldown becomes a readable message and resyncs the card',
    () async {
      when(() => repo.fix()).thenAnswer((_) async => _fix);
      when(() => repo.punch(kind: 'in', fix: _fix)).thenThrow(
        const BadResponseFailure(
          'Please wait three minutes between punches.',
          statusCode: 409,
          code: 'PUNCH_COOLDOWN',
        ),
      );
      when(
        () => repo.myAttendanceSafe(),
      ).thenAnswer((_) async => (data: _today, failure: null));

      final done = bloc.stream.firstWhere((s) => s.message != null);
      bloc.add(const PunchRequested('in'));
      final state = await done;

      expect(state.punching, isFalse);
      expect(state.message, 'Please wait a moment before punching again.');
      verify(() => repo.myAttendanceSafe()).called(1);
    },
  );
}

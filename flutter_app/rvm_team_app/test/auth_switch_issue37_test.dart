import 'package:core_auth/core_auth.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/data/repositories/auth_repository.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/models.dart';
import 'package:rvm_team_app/injection.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAuthSession extends Mock implements AuthSession {}

class _MockEssRepository extends Mock implements EssRepository {}

const _identity = StaffIdentity(
  userId: 'rishi',
  role: AppRole.faculty,
  username: 'Rishi',
);

void main() {
  late _MockAuthRepository repo;
  late _MockAuthSession session;
  late _MockEssRepository ess;
  late TeamAuthBloc bloc;

  setUp(() {
    repo = _MockAuthRepository();
    session = _MockAuthSession();
    ess = _MockEssRepository();
    when(() => session.sessionExpired).thenAnswer((_) => Stream<void>.empty());
    when(() => ess.keepSignInSafe(deviceLabel: any(named: 'deviceLabel')))
        .thenAnswer((_) async => true);
    bloc = TeamAuthBloc(repository: repo, session: session, ess: ess);
  });

  tearDown(() => bloc.close());

  test('signing in drops the previous user\'s kept sign-in first', () async {
    when(() => repo.loginSafe(
          username: 'rishi',
          password: 'pw',
          locationName: 'Faridabad',
        )).thenAnswer((_) async => (
          outcome: const TeamSignedIn(token: 'new-token', identity: _identity),
          failure: null,
        ));
    when(() => session.clearEssSession()).thenAnswer((_) async {});
    when(() =>
            session.saveSchedulerSession(token: 'new-token', role: 'faculty'))
        .thenAnswer((_) async {});

    final authenticated =
        bloc.stream.firstWhere((s) => s.status == TeamAuthStatus.authenticated);
    bloc.add(const TeamLoginSubmitted(
        username: 'rishi', password: 'pw', locationName: 'Faridabad'));
    await authenticated;

    verifyInOrder([
      () => session.clearEssSession(),
      () => session.saveSchedulerSession(token: 'new-token', role: 'faculty'),
    ]);
  });

  test('an unexpected sign-in error becomes a form message, not a crash',
      () async {
    when(() => repo.loginSafe(
          username: 'rishi',
          password: 'pw',
          locationName: 'Faridabad',
        )).thenThrow(StateError('unexpected'));

    final failed =
        bloc.stream.firstWhere((s) => !s.submitting && s.errorMessage != null);
    bloc.add(const TeamLoginSubmitted(
        username: 'rishi', password: 'pw', locationName: 'Faridabad'));
    final state = await failed;

    expect(state.errorMessage, contains('Could not sign in'));
    expect(state.status, TeamAuthStatus.unknown);
  });

  test('sign out clears the session even when the server call throws',
      () async {
    when(() => ess.signOut()).thenThrow(StateError('unexpected'));
    when(() => session.signOutAll()).thenAnswer((_) async {});

    final signedOut = bloc.stream
        .firstWhere((s) => s.status == TeamAuthStatus.unauthenticated);
    bloc.add(const TeamSignedOut());
    await signedOut;

    verify(() => session.signOutAll()).called(1);
  });

  test('the Scheduler client turns 4xx refusals into values, not exceptions',
      () {
    getIt.reset();
    addTearDown(getIt.reset);
    configureDependencies(AuthSession());

    final validate = getIt<Dio>().options.validateStatus;
    expect(validate(200), isTrue);
    expect(validate(400), isTrue);
    expect(validate(409), isTrue);
    expect(validate(503), isTrue);
    // 401 must keep throwing so the bearer interceptor can end the session.
    expect(validate(401), isFalse);
  });
}

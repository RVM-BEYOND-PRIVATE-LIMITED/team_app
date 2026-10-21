import 'dart:convert';

import 'package:core_auth/core_auth.dart';
import 'package:core_network/core_network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/data/repositories/auth_repository.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/domain/ess_models.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAuthSession extends Mock implements AuthSession {}

class _MockEssRepository extends Mock implements EssRepository {}

String _jwt(Map<String, dynamic> payload) {
  final p =
      base64Url.encode(utf8.encode(json.encode(payload))).replaceAll('=', '');
  return 'header.$p.sig';
}

Map<String, dynamic> _teamClaims({required bool expired}) => {
      'role': 'faculty',
      'userId': 'u1',
      'exp': (expired
                  ? DateTime.now().subtract(const Duration(minutes: 5))
                  : DateTime.now().add(const Duration(hours: 1)))
              .millisecondsSinceEpoch ~/
          1000,
    };

void main() {
  late _MockAuthSession session;
  late _MockEssRepository ess;
  late TeamAuthBloc bloc;

  setUp(() {
    session = _MockAuthSession();
    ess = _MockEssRepository();
    when(() => session.sessionExpired).thenAnswer((_) => Stream<void>.empty());
    bloc = TeamAuthBloc(
        repository: _MockAuthRepository(), session: session, ess: ess);
  });

  tearDown(() => bloc.close());

  test('fresh install with no stored session never calls the ESS', () async {
    when(() => session.readSchedulerToken()).thenAnswer((_) async => null);
    when(() => session.readEssRefreshToken()).thenAnswer((_) async => null);

    final unauthenticated = bloc.stream
        .firstWhere((s) => s.status == TeamAuthStatus.unauthenticated);
    bloc.add(const TeamAuthProbeRequested());
    await unauthenticated;

    verifyNever(() => ess.me());
    verifyNever(() => ess.health());
  });

  test('a stored team token restores the session without a network call',
      () async {
    when(() => session.readSchedulerToken())
        .thenAnswer((_) async => _jwt({'role': 'faculty', 'userId': 'u1'}));
    when(() => session.readEssRefreshToken()).thenAnswer((_) async => null);

    final authenticated =
        bloc.stream.firstWhere((s) => s.status == TeamAuthStatus.authenticated);
    bloc.add(const TeamAuthProbeRequested());
    final state = await authenticated;

    expect(state.identity?.userId, 'u1');
    verifyNever(() => ess.me());
  });

  test('a kept sign-in is used to restore an expired token', () async {
    when(() => session.readSchedulerToken()).thenAnswer((_) async => null);
    when(() => session.readEssRefreshToken())
        .thenAnswer((_) async => 'refresh-token');
    when(() => ess.me()).thenThrow(const NoConnectionFailure());

    final unauthenticated = bloc.stream
        .firstWhere((s) => s.status == TeamAuthStatus.unauthenticated);
    bloc.add(const TeamAuthProbeRequested());
    await unauthenticated;

    verify(() => ess.me()).called(1);
  });

  test('a spent token is rotated before the shell can call capabilities',
      () async {
    final calls = <String?>[
      _jwt(_teamClaims(expired: true)),
      _jwt(_teamClaims(expired: false)),
    ];
    when(() => session.readSchedulerToken())
        .thenAnswer((_) async => calls.removeAt(0));
    when(() => session.readEssRefreshToken())
        .thenAnswer((_) async => 'refresh-token');
    when(() => ess.me()).thenAnswer((_) async => EssMe.fromJson(const {}));

    final authenticated =
        bloc.stream.firstWhere((s) => s.status == TeamAuthStatus.authenticated);
    bloc.add(const TeamAuthProbeRequested());
    final state = await authenticated;

    expect(state.identity?.userId, 'u1');
    verify(() => ess.me()).called(1);
  });

  test('a spent token with no kept sign-in is dropped, not used', () async {
    when(() => session.readSchedulerToken())
        .thenAnswer((_) async => _jwt(_teamClaims(expired: true)));
    when(() => session.readEssRefreshToken()).thenAnswer((_) async => null);
    when(() => session.signOutScheduler()).thenAnswer((_) async {});

    final unauthenticated = bloc.stream
        .firstWhere((s) => s.status == TeamAuthStatus.unauthenticated);
    bloc.add(const TeamAuthProbeRequested());
    await unauthenticated;

    verifyNever(() => ess.me());
    verify(() => session.signOutScheduler()).called(1);
  });
}

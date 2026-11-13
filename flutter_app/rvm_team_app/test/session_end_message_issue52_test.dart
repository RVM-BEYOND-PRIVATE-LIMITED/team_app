import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:core_auth/core_auth.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/connectivity_bloc.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/data/repositories/auth_repository.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/features/auth/login_screen.dart';

/// team_app #52, item 8: when the server ends access (an exited account, a
/// changed password, an employee record no longer active), the network layer
/// ends the session with the server's message (core_network
/// SessionRotator.accessEndedMessage) and the sign-in screen shows it. An
/// ordinary expiry still returns to sign-in with nothing to say, as before.
class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAuthSession extends Mock implements AuthSession {}

class _MockEssRepository extends Mock implements EssRepository {}

class _MockTeamAuthBloc extends MockBloc<TeamAuthEvent, TeamAuthState>
    implements TeamAuthBloc {}

class _MockConnectivityBloc
    extends MockBloc<ConnectivityEvent, ConnectivityState>
    implements ConnectivityBloc {}

// The servers' words on main (Scheduler_Backend middleware/auth.js; team_app
// apps/ess-api src/lib/errors.js).
const _exited =
    'This account has been marked exited. Contact a Super Admin if you need '
    'access restored.';
const _passwordChanged = 'Your password was changed. Please sign in again.';

String _liveToken() {
  final claims = base64Url
      .encode(utf8.encode(json.encode({
        'role': 'faculty',
        'userId': 'u-test',
        'exp': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      })))
      .replaceAll('=', '');
  return 'header.$claims.sig';
}

void main() {
  group('TeamAuthBloc', () {
    late StreamController<String?> expired;
    late _MockAuthSession session;
    late TeamAuthBloc bloc;

    setUp(() {
      expired = StreamController<String?>.broadcast();
      session = _MockAuthSession();
      when(() => session.sessionExpired).thenAnswer((_) => expired.stream);
      when(() => session.readSchedulerToken())
          .thenAnswer((_) async => _liveToken());
      when(() => session.readEssRefreshToken()).thenAnswer((_) async => null);
      bloc = TeamAuthBloc(
          repository: _MockAuthRepository(),
          session: session,
          ess: _MockEssRepository());
    });

    tearDown(() async {
      await bloc.close();
      await expired.close();
    });

    Future<void> signIn() async {
      final authenticated = bloc.stream
          .firstWhere((s) => s.status == TeamAuthStatus.authenticated);
      bloc.add(const TeamAuthProbeRequested());
      await authenticated;
    }

    Future<TeamAuthState> expire(String? message) async {
      final next = bloc.stream.first;
      expired.add(message);
      return next;
    }

    test('access ended: back to sign-in with the server\'s message', () async {
      await signIn();

      final state = await expire(_exited);

      expect(state.status, TeamAuthStatus.unauthenticated);
      expect(state.identity, isNull);
      expect(state.errorMessage, _exited);
    });

    test('an ordinary expiry says nothing, as before', () async {
      await signIn();

      final state = await expire(null);

      expect(state.status, TeamAuthStatus.unauthenticated);
      expect(state.errorMessage, isNull);
    });

    test('requests refused after the end keep the server\'s reason', () async {
      await signIn();
      await expire(_passwordChanged);

      // The calls that were in flight come back with no token and no reason.
      expired
        ..add(null)
        ..add(null);
      await pumpEventQueue();

      expect(bloc.state.status, TeamAuthStatus.unauthenticated);
      expect(bloc.state.errorMessage, _passwordChanged);
    });
  });

  group('the sign-in screen', () {
    testWidgets('shows the server\'s reason above Sign in', (tester) async {
      final auth = _MockTeamAuthBloc();
      final connectivity = _MockConnectivityBloc();
      when(() => connectivity.state)
          .thenReturn(const ConnectivityState(online: true));
      when(() => auth.state).thenReturn(const TeamAuthState(
          status: TeamAuthStatus.unauthenticated, errorMessage: _exited));

      await tester.pumpWidget(MultiBlocProvider(
        providers: [
          BlocProvider<TeamAuthBloc>.value(value: auth),
          BlocProvider<ConnectivityBloc>.value(value: connectivity),
        ],
        child: MaterialApp(
            theme: RvmTheme.light(seed: RvmColors.clay),
            home: const LoginScreen()),
      ));
      await tester.pump();

      expect(find.text(_exited), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:core_auth/core_auth.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/connectivity_bloc.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/data/datasources/ess_remote_data_source.dart';
import 'package:rvm_team_app/data/location_service.dart';
import 'package:rvm_team_app/data/repositories/auth_repository.dart';
import 'package:rvm_team_app/data/repositories/ess_repository.dart';
import 'package:rvm_team_app/data/repositories/my_attendance_repository.dart';
import 'package:rvm_team_app/features/attendance/bloc/punch_bloc.dart';
import 'package:rvm_team_app/features/auth/login_screen.dart';
import 'package:rvm_team_app/features/shell/team_shell.dart';
import 'package:rvm_team_app/injection.dart';

/// team_app #52, item 8: when the server ends access (an exited account, a
/// changed password), the network layer ends the session with the server's
/// message (core_network SessionRotator.accessEndedMessage) and the sign-in
/// screen shows it. The same reason reaches the sign-in screen on the next
/// launch when it happened while the app was closed. An ordinary expiry still
/// returns to sign-in with nothing to say, and a 403 NOT_ACTIVE still shows on
/// the screen that asked, as before.
class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAuthSession extends Mock implements AuthSession {}

class _MockEssRepository extends Mock implements EssRepository {}

class _MockTeamAuthBloc extends MockBloc<TeamAuthEvent, TeamAuthState>
    implements TeamAuthBloc {}

class _MockConnectivityBloc
    extends MockBloc<ConnectivityEvent, ConnectivityState>
    implements ConnectivityBloc {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _MockAttendanceRepository extends Mock
    implements MyAttendanceRepository {}

/// The kept sign-in, in memory.
class _EssTokens implements EssTokenStore, TokenStore {
  String? refreshToken = 'refresh-0';

  @override
  Future<String?> readEssRefreshToken() async => refreshToken;

  @override
  Future<String> installId() async => 'install-test';

  @override
  Future<void> saveEssSession({
    required String accessToken,
    required String refreshToken,
    DateTime? accessExpiresAt,
  }) async =>
      this.refreshToken = refreshToken;

  @override
  Future<void> clearEssSession() async => refreshToken = null;

  @override
  Future<String?> readSchedulerToken() async => null;

  @override
  Future<void> onUnauthorized({String? message}) async {}
}

/// Answers every ESS request with [reply].
class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);

  final ResponseBody Function(RequestOptions options) reply;
  final seen = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options.path);
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

/// The ESS's words for each refused refresh (apps/ess-api src/routes/
/// sessions.js REFUSED, src/lib/errors.js MESSAGES on main).
const _essLeft =
    'Your employee record is no longer active, so Team RVM is closed for this '
    'login. Ask HR if this is wrong.';
const _refused = {
  'left': _essLeft,
  'password_changed': 'Your password was changed. Please sign in again.',
  'expired': 'Your sign-in has expired. Please sign in again.',
  'signed_out': 'You have signed out. Please sign in again.',
  'reuse': 'For your safety you have been signed out. Please sign in again.',
};

// The servers' words on main (Scheduler_Backend middleware/auth.js; team_app
// apps/ess-api src/lib/errors.js).
const _exited =
    'This account has been marked exited. Contact a Super Admin if you need '
    'access restored.';
const _passwordChanged = 'Your password was changed. Please sign in again.';

String _liveToken({bool spent = false}) {
  final claims = base64Url
      .encode(utf8.encode(json.encode({
        'role': 'faculty',
        'userId': 'u-test',
        'exp': DateTime.now()
                .add(spent
                    ? const Duration(minutes: -5)
                    : const Duration(hours: 1))
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

  // The exit or the password change happened while the app was closed: the
  // launch restores through the kept sign-in, which the ESS refuses with a
  // reason, and that reason is on the login form.
  group('the next launch', () {
    late _EssTokens tokens;
    late _Adapter adapter;
    late EssRepository ess;
    String? refusal;

    setUp(() {
      tokens = _EssTokens();
      refusal = null;
      adapter = _Adapter((options) {
        final reason = refusal;
        if (reason == null) {
          return _json(200, {
            'session': {'id': 'family-1'},
            'access_token': _liveToken(),
            'access_expires_at':
                DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
            'refresh_token': 'refresh-1',
          });
        }
        return _json(401, {
          'error': _refused[reason] ?? 'Please sign in again.',
          'code': 'NOT_AUTHENTICATED',
          'reason': reason,
        });
      });
      final connectivity = _MockConnectivity();
      when(() => connectivity.isOnline).thenAnswer((_) async => true);
      ess = EssRepository(
        remote: EssRemoteDataSource(
            Dio(BaseOptions(baseUrl: 'https://ess.test/api/ess'))
              ..httpClientAdapter = adapter),
        tokens: tokens,
        schedulerTokens: tokens,
        connectivity: connectivity,
      );
    });

    for (final reason in ['left', 'password_changed']) {
      test('a refresh refused because "$reason" keeps the ESS\'s words',
          () async {
        refusal = reason;

        expect(await ess.restoreKeptSignIn(), isFalse);

        expect(adapter.seen, ['/session/refresh']);
        expect(ess.restoreRefusal, _refused[reason]);
        expect(tokens.refreshToken, isNull, reason: 'the family has ended');
      });
    }

    for (final reason in ['expired', 'signed_out', 'reuse', 'unknown']) {
      test('a refresh refused because "$reason" says nothing, as before',
          () async {
        refusal = reason;

        expect(await ess.restoreKeptSignIn(), isFalse);

        expect(ess.restoreRefusal, isNull);
        expect(tokens.refreshToken, isNull);
      });
    }

    test('a restore that works, or a later one, leaves no reason', () async {
      refusal = 'left';
      expect(await ess.restoreKeptSignIn(), isFalse);
      expect(ess.restoreRefusal, _essLeft);

      // Signed in again since, and this time the kept sign-in renews.
      tokens.refreshToken = 'refresh-new';
      refusal = null;
      expect(await ess.restoreKeptSignIn(), isTrue);
      expect(ess.restoreRefusal, isNull);

      // Nothing kept: nothing sent, and still nothing to say.
      tokens.refreshToken = null;
      expect(await ess.restoreKeptSignIn(), isFalse);
      expect(ess.restoreRefusal, isNull);
    });

    Future<TeamAuthState> launch() async {
      final session = _MockAuthSession();
      when(() => session.sessionExpired)
          .thenAnswer((_) => const Stream<String?>.empty());
      // The hourly token in the slot is spent; the kept sign-in is there.
      when(() => session.readSchedulerToken())
          .thenAnswer((_) async => _liveToken(spent: true));
      when(() => session.readEssRefreshToken())
          .thenAnswer((_) => tokens.readEssRefreshToken());
      when(() => session.signOutScheduler()).thenAnswer((_) async {});
      final bloc = TeamAuthBloc(
          repository: _MockAuthRepository(), session: session, ess: ess);
      addTearDown(bloc.close);
      final settled =
          bloc.stream.firstWhere((s) => s.status != TeamAuthStatus.unknown);
      bloc.add(const TeamAuthProbeRequested());
      return settled;
    }

    test('left while the app was closed: the login form says so', () async {
      refusal = 'left';

      final state = await launch();

      expect(state.status, TeamAuthStatus.unauthenticated);
      expect(state.errorMessage, _essLeft);
    });

    test('password changed while closed: the login form says so', () async {
      refusal = 'password_changed';

      final state = await launch();

      expect(state.status, TeamAuthStatus.unauthenticated);
      expect(state.errorMessage, _passwordChanged);
    });

    test('a kept sign-in that simply expired: the plain form, as before',
        () async {
      refusal = 'expired';

      final state = await launch();

      expect(state.status, TeamAuthStatus.unauthenticated);
      expect(state.errorMessage, isNull);
    });
  });

  // A 403 NOT_ACTIVE is not one of the issue's two codes: it is shown where
  // it was asked for, and the person stays signed in, as before #52.
  group('403 NOT_ACTIVE, as before', () {
    const punchNotActive =
        'Your employee record is not active, so punching is closed.';

    setUpAll(() => registerFallbackValue(const TeamSignedOut()));

    tearDown(() async => getIt.reset());

    testWidgets('the shell shows its access screen, with no sign-out',
        (tester) async {
      await getIt.reset();
      final ess = _MockEssRepository();
      when(() => ess.capabilitiesSafe()).thenAnswer((_) async => (
            data: null,
            failure: const ForbiddenFailure(_essLeft, 'NOT_ACTIVE'),
          ));
      getIt
        ..registerSingleton<EssRepository>(ess)
        ..registerFactory<CapabilitiesBloc>(
            () => CapabilitiesBloc(() async => throw const UnknownFailure()));
      final auth = _MockTeamAuthBloc();
      when(() => auth.state).thenReturn(const TeamAuthState(
        status: TeamAuthStatus.authenticated,
        identity: StaffIdentity(userId: 'u-test', role: AppRole.faculty),
      ));

      await tester.pumpWidget(BlocProvider<TeamAuthBloc>.value(
        value: auth,
        child: MaterialApp(
            theme: RvmTheme.light(seed: RvmColors.clay),
            home: const TeamShell()),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text(_essLeft), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(tester.takeException(), isNull);
      verifyNever(() => auth.add(any()));
    });

    test('the punch card shows the refusal inline', () async {
      const fix = LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyM: 5,
        mocked: false,
      );
      final repo = _MockAttendanceRepository();
      when(() => repo.fix()).thenAnswer((_) async => fix);
      when(() => repo.punch(kind: 'in', fix: fix))
          .thenThrow(const ForbiddenFailure(punchNotActive, 'NOT_ACTIVE'));
      final session = _MockAuthSession();
      final bloc = PunchBloc(repo, _MockEssRepository(), session);
      addTearDown(bloc.close);

      final done = bloc.stream.firstWhere((s) => s.message != null);
      bloc.add(const PunchRequested('in'));
      final state = await done;

      expect(state.punching, isFalse);
      expect(state.message, punchNotActive);
      verifyNever(() => session.onUnauthorized(message: any(named: 'message')));
      verifyNever(() => session.signOutScheduler());
    });
  });
}

import 'package:core_bloc/core_bloc.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/bloc/team_auth_bloc.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/me/account_security_screen.dart';
import 'package:rvm_team_app/features/me/me_screen.dart';
import 'package:rvm_team_app/injection.dart';
import 'package:rvm_team_app/router/app_router.dart';

/// Issue #13: an attendance-only sign-in must never touch a Scheduler-only
/// screen, must show the ESS account card, and a wrong password must not be
/// treated as an expired session.
class _MockTeamAuthBloc extends Mock implements TeamAuthBloc {}

class _MockCapabilitiesBloc extends Mock
    implements LoadBloc<EssCapabilities> {}

const _identity = StaffIdentity(
  userId: 'e1',
  role: AppRole.unknown,
  attendance: true,
);

TeamAuthState _authState() => const TeamAuthState(
      status: TeamAuthStatus.authenticated,
      identity: _identity,
      attendanceName: 'Mohit',
    );

void _stubAuth(_MockTeamAuthBloc auth) {
  when(() => auth.state).thenReturn(_authState());
  when(() => auth.stream)
      .thenAnswer((_) => const Stream<TeamAuthState>.empty());
}

_MockCapabilitiesBloc _stubCaps() {
  final caps = _MockCapabilitiesBloc();
  when(() => caps.state).thenReturn(const LoadState<EssCapabilities>());
  when(() => caps.stream)
      .thenAnswer((_) => const Stream<LoadState<EssCapabilities>>.empty());
  return caps;
}

EssMe _me() => const EssMe(
      employee: EssEmployee(
        id: 'e1',
        fullName: 'Mohit',
        employeeCode: 'RVM/F/48',
        designation: 'Mobile App Developer',
        employmentStatus: 'active',
        department: EssOrganizationRef(id: 'd1', name: 'Engineering / IT'),
        branch: EssOrganizationRef(id: 'b1', name: 'Faridabad'),
      ),
      login: EssLogin(kind: 'attendance'),
    );

const _account = EssAccount(
  loginKind: 'attendance',
  username: 'RVM/0217',
  email: 'mohit@rvmcad.org',
  emailVerified: true,
  phoneNumber: '9876500020',
  canChangeEmail: false,
  canChangePhone: false,
  canChangePassword: true,
  canUseTwoFactor: false,
  note: 'Ask HR to change your email or phone number. You can change your password here.',
);

void main() {
  setUp(() => getIt.reset());
  tearDown(() => getIt.reset());

  group('the route guard', () {
    test('blocks every Scheduler-only location for an attendance session', () {
      for (final location in [
        '/account/security-events',
        '/helpdesk/queue',
        '/leaders',
        '/work/batches',
        '/work/indicators',
        '/work/interviews',
        '/work/my-day',
        '/work/batch/abc/mark',
        '/work/hod',
        '/hr/tools',
        '/hr/change-requests',
      ]) {
        expect(attendanceBlockedLocation(location), isTrue, reason: location);
      }
    });

    test('keeps the ESS surface and the shared account screen open', () {
      for (final location in [
        '/home',
        '/account/security',
        '/me/profile',
        '/me/personal',
        '/me/documents',
        '/me/bank',
        '/me/id-card',
        '/me/data-requests',
        '/me/sessions',
        '/me/attendance',
        '/requests',
        '/helpdesk',
        '/helpdesk/ticket/1',
        '/wall/post/1',
        '/team/directory',
        '/notifications',
      ]) {
        expect(attendanceBlockedLocation(location), isFalse, reason: location);
      }
    });
  });

  testWidgets('Me for attendance: ESS header, no Scheduler-only tiles',
      (tester) async {
    getIt.registerFactory<LoadBloc<EssMe>>(
        () => LoadBloc<EssMe>(() async => _me()));
    final auth = _MockTeamAuthBloc();
    _stubAuth(auth);
    final caps = _stubCaps();

    await tester.pumpWidget(MaterialApp(
      home: BlocProvider<TeamAuthBloc>.value(
        value: auth,
        child: BlocProvider<CapabilitiesBloc>.value(
          value: caps,
          child: const MeScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Header comes from the ESS /me, not the Scheduler.
    expect(find.text('ATTENDANCE'), findsOneWidget);
    expect(find.text('Mobile App Developer'), findsOneWidget);

    // Scroll to the bottom so the account/support section is built.
    await tester.drag(find.byType(ListView), const Offset(0, -2200));
    await tester.pumpAndSettle();

    expect(find.text('Account & security'), findsOneWidget);
    expect(find.text('Password; email and phone via HR'), findsOneWidget);
    // Scheduler-only tiles are not offered to this session.
    expect(find.text('Security activity'), findsNothing);
    expect(find.text('My batches'), findsNothing);
    expect(find.text('My indicators'), findsNothing);
    expect(find.text('Interviews'), findsNothing);
    expect(find.text('HR tools'), findsNothing);
    expect(find.text('Faculty Development'), findsNothing);
  });

  testWidgets('Account & Security for attendance uses the ESS card',
      (tester) async {
    getIt.registerFactory<LoadBloc<EssAccount>>(
        () => LoadBloc<EssAccount>(() async => _account));
    final auth = _MockTeamAuthBloc();
    _stubAuth(auth);
    final caps = _stubCaps();

    await tester.pumpWidget(MaterialApp(
      home: BlocProvider<TeamAuthBloc>.value(
        value: auth,
        child: BlocProvider<CapabilitiesBloc>.value(
          value: caps,
          child: const AccountSecurityScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The ESS card: identifiers read-only, password change.
    expect(find.text('RVM/0217'), findsOneWidget);
    expect(find.text('Employee code'), findsOneWidget);
    expect(find.text('mohit@rvmcad.org'), findsOneWidget);
    expect(find.text('9876500020'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.textContaining('Ask HR to change your email or phone'),
        findsOneWidget);
    expect(find.text('Current password'), findsOneWidget);
    expect(find.text('Update password'), findsOneWidget);

    // Nothing from the Scheduler's Account & Security.
    expect(find.text('Two-factor sign-in'), findsNothing);
    expect(find.text('Verify Now'), findsNothing);
    expect(find.text('Change email'), findsNothing);
    expect(find.text('Change phone number'), findsNothing);
    expect(find.text('Security Center'), findsNothing);
  });

  testWidgets('attendance header falls back to the login name while /me loads',
      (tester) async {
    getIt.registerFactory<LoadBloc<EssMe>>(
        () => LoadBloc<EssMe>(() async => throw StateError('offline')));
    final auth = _MockTeamAuthBloc();
    _stubAuth(auth);
    final caps = _stubCaps();

    await tester.pumpWidget(MaterialApp(
      home: BlocProvider<TeamAuthBloc>.value(
        value: auth,
        child: BlocProvider<CapabilitiesBloc>.value(
          value: caps,
          child: const MeScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Mohit'), findsOneWidget);
  });
}

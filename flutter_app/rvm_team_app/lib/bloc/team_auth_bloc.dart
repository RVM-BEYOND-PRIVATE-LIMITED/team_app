import 'dart:async';
import 'dart:io';

import 'package:core_auth/core_auth.dart';
import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/ess_repository.dart';
import '../domain/models.dart';

// ── events ──────────────────────────────────────────────────────────────
sealed class TeamAuthEvent {
  const TeamAuthEvent();
}

/// Restore the session on launch by decoding the stored JWT (no /me needed).
class TeamAuthProbeRequested extends TeamAuthEvent {
  const TeamAuthProbeRequested();
}

class TeamLoginSubmitted extends TeamAuthEvent {
  const TeamLoginSubmitted(
      {required this.username,
      required this.password,
      required this.locationName});
  final String username;
  final String password;
  final String locationName;
}

class TeamTwoFactorSubmitted extends TeamAuthEvent {
  const TeamTwoFactorSubmitted(this.code);
  final String code;
}

/// No resend endpoint: re-POSTing /users/login issues a fresh code.
class TeamTwoFactorResendRequested extends TeamAuthEvent {
  const TeamTwoFactorResendRequested();
}

class TeamTwoFactorCancelled extends TeamAuthEvent {
  const TeamTwoFactorCancelled();
}

/// Switch the login form between portal sign-in and attendance-only sign-in.
class TeamAttendanceModeToggled extends TeamAuthEvent {
  const TeamAttendanceModeToggled(this.attendance);
  final bool attendance;
}

/// Attendance-only sign-in by password (A2): phone / email / employee code.
class TeamAttendanceLoginSubmitted extends TeamAuthEvent {
  const TeamAttendanceLoginSubmitted(
      {required this.identifier, required this.password});
  final String identifier;
  final String password;
}

/// Ask for a sign-in code (the route out of a lock or a forgotten password).
class TeamAttendanceCodeRequested extends TeamAuthEvent {
  const TeamAttendanceCodeRequested(this.identifier);
  final String identifier;
}

class TeamAttendanceCodeSubmitted extends TeamAuthEvent {
  const TeamAttendanceCodeSubmitted(
      {required this.challengeId, required this.code});
  final String challengeId;
  final String code;
}

class TeamAttendanceBack extends TeamAuthEvent {
  const TeamAttendanceBack();
}

class TeamSignedOut extends TeamAuthEvent {
  const TeamSignedOut();
}

class TeamSessionExpired extends TeamAuthEvent {
  const TeamSessionExpired();
}

// ── state ───────────────────────────────────────────────────────────────
enum TeamAuthStatus { unknown, unauthenticated, authenticated }

class TeamAuthState extends Equatable {
  const TeamAuthState({
    this.status = TeamAuthStatus.unknown,
    this.identity,
    this.submitting = false,
    this.errorMessage,
    this.twoFactor,
    this.attendanceMode = false,
    this.attendanceCode,
    this.attendanceName,
    this.mustSetAttendancePassword = false,
  });

  final TeamAuthStatus status;
  final StaffIdentity? identity;
  final bool submitting;
  final String? errorMessage;
  final TeamTwoFactorChallenge? twoFactor;

  /// The login form is in attendance-only mode.
  final bool attendanceMode;

  /// A code was sent; show the code step.
  final AttendanceCodeSent? attendanceCode;

  /// The attendance employee's name (for the set-password prompt).
  final String? attendanceName;

  /// The session cannot punch until a new attendance password is chosen.
  final bool mustSetAttendancePassword;

  TeamAuthState copyWith({
    TeamAuthStatus? status,
    StaffIdentity? identity,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
    TeamTwoFactorChallenge? twoFactor,
    bool clearTwoFactor = false,
    bool? attendanceMode,
    AttendanceCodeSent? attendanceCode,
    bool clearAttendanceCode = false,
    String? attendanceName,
    bool? mustSetAttendancePassword,
  }) =>
      TeamAuthState(
        status: status ?? this.status,
        identity: identity ?? this.identity,
        submitting: submitting ?? this.submitting,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        twoFactor: clearTwoFactor ? null : (twoFactor ?? this.twoFactor),
        attendanceMode: attendanceMode ?? this.attendanceMode,
        attendanceCode: clearAttendanceCode
            ? null
            : (attendanceCode ?? this.attendanceCode),
        attendanceName: attendanceName ?? this.attendanceName,
        mustSetAttendancePassword:
            mustSetAttendancePassword ?? this.mustSetAttendancePassword,
      );

  @override
  List<Object?> get props => [
        status,
        identity?.userId,
        submitting,
        errorMessage,
        twoFactor?.challengeId,
        attendanceMode,
        attendanceCode?.challengeId,
        mustSetAttendancePassword,
      ];
}

/// Owns the Team RVM session — ONE role per session. UI-agnostic: talks to the
/// [AuthRepository] + [AuthSession] only (never dio / BuildContext).
class TeamAuthBloc extends Bloc<TeamAuthEvent, TeamAuthState> {
  TeamAuthBloc({
    required AuthRepository repository,
    required AuthSession session,
    required EssRepository ess,
  })  : _repo = repository,
        _session = session,
        _ess = ess,
        super(const TeamAuthState()) {
    on<TeamAuthProbeRequested>(_onProbe);
    on<TeamLoginSubmitted>(_onLogin);
    on<TeamTwoFactorSubmitted>(_onTwoFactorCode);
    on<TeamTwoFactorResendRequested>(_onTwoFactorResend);
    on<TeamTwoFactorCancelled>(_onTwoFactorCancelled);
    on<TeamAttendanceModeToggled>((e, emit) => emit(state.copyWith(
        attendanceMode: e.attendance,
        clearError: true,
        clearAttendanceCode: true)));
    on<TeamAttendanceLoginSubmitted>(_onAttendanceLogin);
    on<TeamAttendanceCodeRequested>(_onAttendanceCodeRequested);
    on<TeamAttendanceCodeSubmitted>(_onAttendanceCodeSubmitted);
    on<TeamAttendanceBack>((e, emit) =>
        emit(state.copyWith(clearAttendanceCode: true, clearError: true)));
    on<TeamSignedOut>(_onSignedOut);
    on<TeamSessionExpired>((e, emit) =>
        emit(const TeamAuthState(status: TeamAuthStatus.unauthenticated)));

    // React to a 401 anywhere (BearerAuthInterceptor → session.onUnauthorized).
    _expirySub =
        _session.sessionExpired.listen((_) => add(const TeamSessionExpired()));
  }

  final AuthRepository _repo;
  final AuthSession _session;
  final EssRepository _ess;
  late final StreamSubscription<void> _expirySub;

  /// Credentials of an in-flight 2FA login, kept in memory only (never in state).
  TeamLoginSubmitted? _pending;

  Future<void> _onProbe(
      TeamAuthProbeRequested e, Emitter<TeamAuthState> emit) async {
    try {
      var token = await _session.readSchedulerToken();
      var identity = StaffIdentity.fromToken(token);
      // The ESS access token (1 hour) replaces the Scheduler one (64 hours) in
      // the same slot, so a stored token is often spent by the next launch. A
      // spent token must never be handed to /me/capabilities: the ESS would
      // answer 401 and the shell would open on an error. Treat it as absent and
      // restore through the kept sign-in instead.
      final stale =
          identity == null || !identity.isTeamMember || Jwt.isExpired(token);
      // Only a device that already holds a session has anything to restore. A
      // fresh install must go straight to the login screen without touching the
      // network: the very first cold-start call can race the OS resolver and
      // surface `Failed host lookup` on the splash screen.
      final hasKeptSignIn = await _session.readEssRefreshToken() != null;
      if (stale && hasKeptSignIn) {
        // Rotate the kept sign-in directly. This is the one launch call that is
        // EXPECTED to answer 401 when the sign-in has ended; it must come back
        // as a value, never as a thrown DioException the debugger pauses on.
        final restored = await _ess.restoreKeptSignIn();
        if (restored) {
          token = await _session.readSchedulerToken();
          identity = StaffIdentity.fromToken(token);
        }
      }
      if (identity == null || !identity.isTeamMember || Jwt.isExpired(token)) {
        // A dead token would only draw 401s; drop it so the next screen is the
        // login form, not the shell's error state.
        if (token != null) await _session.signOutScheduler();
        emit(const TeamAuthState(status: TeamAuthStatus.unauthenticated));
        return;
      }
      emit(TeamAuthState(
          status: TeamAuthStatus.authenticated, identity: identity));
    } catch (_) {
      // A restore that throws for any reason must not crash the first frame.
      emit(const TeamAuthState(status: TeamAuthStatus.unauthenticated));
    }
  }

  // ── Attendance-only sign-in (A2) ────────────────────────────────────────

  Future<void> _onAttendanceLogin(
      TeamAttendanceLoginSubmitted e, Emitter<TeamAuthState> emit) async {
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      final result = await _repo.attendancePasswordLogin(
          identifier: e.identifier, password: e.password);
      await _finishAttendance(result, emit);
    } on Failure catch (f) {
      emit(state.copyWith(submitting: false, errorMessage: _message(f)));
    }
  }

  Future<void> _onAttendanceCodeRequested(
      TeamAttendanceCodeRequested e, Emitter<TeamAuthState> emit) async {
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      final sent = await _repo.requestAttendanceCode(e.identifier);
      emit(state.copyWith(submitting: false, attendanceCode: sent));
    } on Failure catch (f) {
      emit(state.copyWith(submitting: false, errorMessage: _message(f)));
    }
  }

  Future<void> _onAttendanceCodeSubmitted(
      TeamAttendanceCodeSubmitted e, Emitter<TeamAuthState> emit) async {
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      final result = await _repo.verifyAttendanceCode(
          challengeId: e.challengeId, code: e.code);
      await _finishAttendance(result, emit);
    } on Failure catch (f) {
      emit(state.copyWith(submitting: false, errorMessage: _message(f)));
    }
  }

  Future<void> _finishAttendance(
      AttendanceLoginResult result, Emitter<TeamAuthState> emit) async {
    await _session.saveSchedulerSession(token: result.token);
    emit(TeamAuthState(
      status: TeamAuthStatus.authenticated,
      identity: StaffIdentity.fromToken(result.token),
      attendanceName: result.employeeName,
      mustSetAttendancePassword: result.temporary || !result.passwordSet,
    ));
    unawaited(_keepSignIn());
  }

  Future<void> _onLogin(
      TeamLoginSubmitted e, Emitter<TeamAuthState> emit) async {
    emit(state.copyWith(
        submitting: true, clearError: true, clearTwoFactor: true));
    _pending = e;
    try {
      final result = await _repo.loginSafe(
          username: e.username,
          password: e.password,
          locationName: e.locationName);
      if (result.failure != null) {
        _pending = null;
        emit(state.copyWith(
            submitting: false, errorMessage: _message(result.failure!)));
        return;
      }
      await _onOutcome(result.outcome!, emit);
    } on Failure catch (f) {
      _pending = null;
      emit(state.copyWith(submitting: false, errorMessage: _message(f)));
    }
  }

  Future<void> _onTwoFactorCode(
      TeamTwoFactorSubmitted e, Emitter<TeamAuthState> emit) async {
    final challenge = state.twoFactor;
    if (challenge == null) return;
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      final signedIn = await _repo.verifyTwoFactor(
        challengeId: challenge.challengeId,
        code: e.code,
        locationName: challenge.locationName,
      );
      await _completeSignIn(signedIn, emit);
    } on Failure catch (f) {
      emit(state.copyWith(submitting: false, errorMessage: _message(f)));
    }
  }

  Future<void> _onTwoFactorResend(
      TeamTwoFactorResendRequested e, Emitter<TeamAuthState> emit) async {
    final pending = _pending;
    if (pending == null || state.twoFactor == null) return;
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      final result = await _repo.loginSafe(
        username: pending.username,
        password: pending.password,
        locationName: pending.locationName,
      );
      if (result.failure != null) {
        emit(state.copyWith(
            submitting: false, errorMessage: _message(result.failure!)));
        return;
      }
      await _onOutcome(result.outcome!, emit);
    } on Failure catch (f) {
      emit(state.copyWith(submitting: false, errorMessage: _message(f)));
    }
  }

  void _onTwoFactorCancelled(
      TeamTwoFactorCancelled e, Emitter<TeamAuthState> emit) {
    _pending = null;
    emit(state.copyWith(
        submitting: false, clearError: true, clearTwoFactor: true));
  }

  Future<void> _onOutcome(
      TeamLoginOutcome outcome, Emitter<TeamAuthState> emit) async {
    switch (outcome) {
      case TeamTwoFactorRequired():
        emit(state.copyWith(submitting: false, twoFactor: outcome.challenge));
      case TeamSignedIn():
        await _completeSignIn(outcome, emit);
    }
  }

  Future<void> _completeSignIn(
      TeamSignedIn signedIn, Emitter<TeamAuthState> emit) async {
    _pending = null;
    final identity = signedIn.identity;
    if (!identity.isTeamMember) {
      emit(state.copyWith(
        submitting: false,
        errorMessage:
            'This account (${appRoleWire(identity.role) ?? 'unknown'}) has no Team RVM access.',
        clearTwoFactor: true,
      ));
      return;
    }
    await _session.saveSchedulerSession(
        token: signedIn.token, role: appRoleWire(identity.role));
    emit(TeamAuthState(
        status: TeamAuthStatus.authenticated, identity: identity));
    // Swap the fresh sign-in for a kept, rotating one (task A3). Best-effort:
    // a failure must never block a successful sign-in.
    unawaited(_keepSignIn());
  }

  Future<void> _keepSignIn() async {
    // Non-throwing: an HR login that is not linked to an employee record gets
    // 403 NOT_LINKED on /session. That only skips the kept-sign-in upgrade; the
    // Scheduler token still works and the shell's access gate explains the link.
    await _ess.keepSignInSafe(
        deviceLabel: 'Team RVM · ${Platform.operatingSystem}');
  }

  Future<void> _onSignedOut(
      TeamSignedOut e, Emitter<TeamAuthState> emit) async {
    _pending = null;
    try {
      await _ess.signOut();
    } on Failure {
      // Sign out locally even if the server call fails.
    }
    await _session.signOutAll();
    emit(const TeamAuthState(status: TeamAuthStatus.unauthenticated));
  }

  /// State the real, actionable cause. /users/login answers 404 for an unknown
  /// user/branch, 401 only for a wrong password.
  String _message(Failure f) {
    if (f is UnauthorizedFailure) {
      return 'Incorrect password. Try again, or use “Forgot password?”.';
    }
    return switch (f.code) {
      'TWO_FACTOR_UNAVAILABLE' ||
      'MAIL_FAILED' ||
      'MAIL_NOT_CONFIGURED' =>
        'Two-step sign-in is on for this account, but the code email could not be sent. Try again shortly.',
      'WRONG_CREDENTIALS' => f.message,
      'LOCKED' => f.message,
      'HAS_PORTAL_LOGIN' => f.message,
      'NO_ATTENDANCE_LOGIN' => f.message,
      'PASSWORD_NOT_SET' =>
        'Set an attendance password with a sign-in code first.',
      _ => f.message,
    };
  }

  @override
  Future<void> close() async {
    await _expirySub.cancel();
    return super.close();
  }
}

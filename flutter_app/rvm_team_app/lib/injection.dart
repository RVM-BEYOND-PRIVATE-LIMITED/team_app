import 'package:core_auth/core_auth.dart';
import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import 'bloc/connectivity_bloc.dart';
import 'bloc/forgot_password_bloc.dart';
import 'bloc/team_auth_bloc.dart';
import 'data/datasources/announcements_remote_data_source.dart';
import 'data/datasources/auth_remote_data_source.dart';
import 'data/datasources/ess_remote_data_source.dart';
import 'data/datasources/hod_remote_data_source.dart';
import 'data/datasources/me_remote_data_source.dart';
import 'data/datasources/my_attendance_remote_data_source.dart';
import 'data/datasources/priority_tasks_remote_data_source.dart';
import 'data/datasources/work_remote_data_source.dart';
import 'data/location_service.dart';
import 'data/repositories/announcements_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/ess_repository.dart';
import 'data/repositories/hod_repository.dart';
import 'data/repositories/me_repository.dart';
import 'data/repositories/my_attendance_repository.dart';
import 'data/repositories/priority_tasks_repository.dart';
import 'data/repositories/work_repository.dart';
import 'domain/ess_models.dart';
import 'domain/models.dart';
import 'features/attendance/bloc/punch_bloc.dart';
import 'features/hod/bloc/hod_write_bloc.dart';
import 'features/hr/bloc/employee_personal_bloc.dart';
import 'features/hr/bloc/hr_tools_bloc.dart';
import 'features/inbox/bloc/task_action_bloc.dart';
import 'features/me/bloc/account_action_bloc.dart';
import 'features/me/bloc/attendance_day_bloc.dart';
import 'features/me/bloc/data_requests_bloc.dart';
import 'features/me/bloc/personal_bloc.dart';
import 'features/me/bloc/sessions_bloc.dart';
import 'features/helpdesk/bloc/helpdesk_bloc.dart';
import 'features/my_team/bloc/team_today_bloc.dart';
import 'features/notifications/bloc/notifications_bloc.dart';
import 'features/requests/bloc/approvals_bloc.dart';
import 'features/wall/bloc/wall_bloc.dart';
import 'features/requests/bloc/requests_bloc.dart';
import 'features/work/bloc/absent_remark_bloc.dart';
import 'features/work/bloc/interview_action_bloc.dart';
import 'features/work/bloc/mark_attendance_bloc.dart';

/// Service locator — same provided stack as staff_app / student_app:
/// get_it + dio behind the data layer + bloc. Blocs get deps by constructor;
/// dio never leaves the data layer.
final getIt = GetIt.instance;

// LoadBloc instances get readable names by type.
typedef MeBloc = LoadBloc<TeamProfile>;
typedef InboxBloc = LoadBloc<PriorityInbox>;
typedef MyBatchesBloc = LoadBloc<List<TeamBatch>>;
typedef InterviewsBloc = LoadBloc<List<InterviewRound>>;

/// The full interview list (as opposed to [InterviewsBloc], the upcoming ones).
/// A distinct type so both can live in GetIt — two typedefs for the same
/// `LoadBloc<List<InterviewRound>>` would collide on registration.
class InterviewsListBloc extends LoadBloc<List<InterviewRound>> {
  // LoadBloc's fetch parameter is private, so a super parameter cannot name it.
  // ignore: use_super_parameters
  InterviewsListBloc(
    Future<List<InterviewRound>> Function() fetch, {
    bool Function(List<InterviewRound>)? isEmpty,
  }) : super(fetch, isEmpty: isEmpty);
}

typedef HomeAnnouncementsBloc = LoadBloc<List<TeamAnnouncement>>;
typedef SecurityEventsBloc = LoadBloc<List<SecurityEvent>>;
typedef HodOverviewBloc = LoadBloc<HodOverview>;
typedef HodInterviewsBloc = LoadBloc<List<HodInterview>>;
typedef HodFacultyOptionsBloc = LoadBloc<List<FacultyOption>>;
typedef FacultyReportBloc = LoadBloc<FacultyReport>;
typedef CapabilitiesBloc = LoadBloc<EssCapabilities>;

/// Wires the whole graph at startup. [session] is the hydrated auth session.
void configureDependencies(AuthSession session) {
  getIt
    ..registerSingleton<AuthSession>(session)
    ..registerLazySingleton<ConnectivityService>(ConnectivityService.new)
    ..registerLazySingleton<ApiEnvironment>(ApiEnvironment.fromDefines)
    // Scheduler client: bearer JWT + the persistent punch device cookie (B8/B13).
    ..registerLazySingleton<Dio>(() => DioFactory.scheduler(
          env: getIt<ApiEnvironment>(),
          tokens: getIt<AuthSession>(),
          cookieJar: getIt<AuthSession>().schedulerCookieJar,
          logging: kDebugMode,
        ))
    // ESS client: bearer + rotating kept sign-in (A3).
    ..registerLazySingleton<Dio>(
      () {
        final dio = DioFactory.ess(
          env: getIt<ApiEnvironment>(),
          tokens: getIt<AuthSession>(),
          essTokens: getIt<AuthSession>(),
          logging: kDebugMode,
        );
        // Let refused responses reach the data source as a typed Failure instead
        // of throwing a DioException. The debugger stops on every thrown error
        // even when the app catches it (a 503 on the Wall and a 400 on a request
        // form used to surface that way), and a server 4xx/5xx is a result the UI
        // must render, not a crash. A 401 still throws: the EssAuthInterceptor's
        // kept-sign-in rotation runs on that error, and a rejected token must end
        // the session rather than become a plain reply.
        dio.options.validateStatus = (status) =>
            status != null &&
            ((status >= 200 && status < 300) ||
                (status >= 400 && status != 401));
        return dio;
      },
      instanceName: 'ess',
    );

  // Data sources (dio stays here).
  getIt
    ..registerLazySingleton<AuthRemoteDataSource>(
        () => AuthRemoteDataSource(getIt<Dio>()))
    ..registerLazySingleton<MeRemoteDataSource>(
        () => MeRemoteDataSource(getIt<Dio>()))
    ..registerLazySingleton<PriorityTasksRemoteDataSource>(
        () => PriorityTasksRemoteDataSource(getIt<Dio>()))
    ..registerLazySingleton<WorkRemoteDataSource>(
        () => WorkRemoteDataSource(getIt<Dio>()))
    ..registerLazySingleton<AnnouncementsRemoteDataSource>(
        () => AnnouncementsRemoteDataSource(getIt<Dio>()))
    ..registerLazySingleton<HodRemoteDataSource>(
        () => HodRemoteDataSource(getIt<Dio>()))
    ..registerLazySingleton<EssRemoteDataSource>(
        () => EssRemoteDataSource(getIt<Dio>(instanceName: 'ess')))
    ..registerLazySingleton<MyAttendanceRemoteDataSource>(
        () => MyAttendanceRemoteDataSource(getIt<Dio>()))
    ..registerLazySingleton<LocationService>(LocationService.new);

  // Repositories.
  getIt
    ..registerLazySingleton<AuthRepository>(
        () => AuthRepository(remote: getIt(), connectivity: getIt()))
    ..registerLazySingleton<MeRepository>(
        () => MeRepository(remote: getIt(), connectivity: getIt()))
    ..registerLazySingleton<EssRepository>(() => EssRepository(
          remote: getIt(),
          tokens: getIt<AuthSession>(),
          connectivity: getIt(),
        ))
    ..registerLazySingleton<PriorityTasksRepository>(
        () => PriorityTasksRepository(remote: getIt(), connectivity: getIt()))
    ..registerLazySingleton<WorkRepository>(
        () => WorkRepository(remote: getIt(), connectivity: getIt()))
    ..registerLazySingleton<HodRepository>(
        () => HodRepository(remote: getIt(), connectivity: getIt()))
    ..registerLazySingleton<AnnouncementsRepository>(
        () => AnnouncementsRepository(remote: getIt(), connectivity: getIt()))
    ..registerLazySingleton<MyAttendanceRepository>(
        () => MyAttendanceRepository(
              remote: getIt(),
              location: getIt(),
              connectivity: getIt(),
            ));

  // Session-wide blocs.
  getIt
    ..registerLazySingleton<TeamAuthBloc>(
        () => TeamAuthBloc(repository: getIt(), session: getIt(), ess: getIt()))
    ..registerLazySingleton<ConnectivityBloc>(() => ConnectivityBloc(getIt()));

  // Feature blocs.
  getIt
    ..registerFactory<ForgotPasswordBloc>(() => ForgotPasswordBloc(getIt()))
    ..registerFactory<AccountActionBloc>(() => AccountActionBloc(getIt()))
    ..registerFactory<TaskActionBloc>(() => TaskActionBloc(getIt()))
    ..registerFactory<MeBloc>(
        () => LoadBloc<TeamProfile>(() => getIt<MeRepository>().me()))
    ..registerFactory<InboxBloc>(() =>
        LoadBloc<PriorityInbox>(() => getIt<PriorityTasksRepository>().inbox()))
    ..registerFactory<MyBatchesBloc>(() => LoadBloc<List<TeamBatch>>(
        () => getIt<WorkRepository>().batches(),
        isEmpty: (l) => l.isEmpty))
    ..registerFactory<InterviewsBloc>(() => LoadBloc<List<InterviewRound>>(
        () => getIt<WorkRepository>().upcomingInterviews(),
        isEmpty: (l) => l.isEmpty))
    ..registerFactory<HomeAnnouncementsBloc>(() =>
        LoadBloc<List<TeamAnnouncement>>(
            () => getIt<AnnouncementsRepository>().list(),
            isEmpty: (l) => l.isEmpty))
    ..registerFactory<SecurityEventsBloc>(() => LoadBloc<List<SecurityEvent>>(
        () => getIt<MeRepository>().securityEvents(),
        isEmpty: (l) => l.isEmpty))
    ..registerFactory<InterviewsListBloc>(() => InterviewsListBloc(
        () => getIt<WorkRepository>().interviews(),
        isEmpty: (l) => l.isEmpty))
    ..registerFactory<HodOverviewBloc>(
        () => LoadBloc<HodOverview>(() => getIt<HodRepository>().overview()))
    ..registerFactory<HodInterviewsBloc>(() => LoadBloc<List<HodInterview>>(
        () => getIt<HodRepository>().interviews(),
        isEmpty: (l) => l.isEmpty))
    ..registerFactory<HodFacultyOptionsBloc>(() =>
        LoadBloc<List<FacultyOption>>(
            () => getIt<HodRepository>().facultyOptions(),
            isEmpty: (l) => l.isEmpty))
    ..registerFactoryParam<FacultyReportBloc, String, void>((facultyId, _) =>
        LoadBloc<FacultyReport>(() => getIt<WorkRepository>().facultyReport(
            facultyId,
            startDate: _monthStart(),
            endDate: _today())))
    ..registerFactory<AbsentRemarkBloc>(() => AbsentRemarkBloc(getIt()))
    ..registerFactory<HodWriteBloc>(() => HodWriteBloc(getIt()))
    ..registerFactory<InterviewActionBloc>(() => InterviewActionBloc(getIt()))
    // ── Team RVM ESS (1A/1B) ──────────────────────────────────────────────
    ..registerFactory<CapabilitiesBloc>(() =>
        LoadBloc<EssCapabilities>(() => getIt<EssRepository>().capabilities()))
    ..registerFactory<PersonalBloc>(() => PersonalBloc(getIt()))
    ..registerFactory<DataRequestsBloc>(() => DataRequestsBloc(getIt()))
    ..registerFactory<AttendanceDayBloc>(() => AttendanceDayBloc(getIt()))
    ..registerFactory<SessionsBloc>(() => SessionsBloc(getIt()))
    ..registerFactory<HrToolsBloc>(() => HrToolsBloc(getIt()))
    ..registerFactory<PunchBloc>(
        () => PunchBloc(getIt(), getIt(), getIt<AuthSession>()))
    ..registerFactoryParam<EmployeePersonalBloc, String, void>(
        (employeeId, _) => EmployeePersonalBloc(getIt(), employeeId))
    // ── Team RVM ESS (1E: Me & My Team) ───────────────────────────────────
    ..registerFactory<TeamTodayBloc>(() => TeamTodayBloc(getIt()))
    ..registerFactory<LoadBloc<OrgView>>(
        () => LoadBloc<OrgView>(() => getIt<EssRepository>().myOrg()))
    ..registerFactory<LoadBloc<TeamOffWeek>>(() =>
        LoadBloc<TeamOffWeek>(() => getIt<EssRepository>().teamOffThisWeek()))
    ..registerFactory<LoadBloc<MyProfile>>(
        () => LoadBloc<MyProfile>(() => getIt<EssRepository>().myProfile()))
    ..registerFactory<LoadBloc<PraisePage>>(
        () => LoadBloc<PraisePage>(() => getIt<EssRepository>().myPraise()))
    // ── Team RVM ESS (2D: leaders) ───────────────────────────────────────
    ..registerFactory<LoadBloc<LeadersOverview>>(() =>
        LoadBloc<LeadersOverview>(
            () => getIt<EssRepository>().leadersOverview()))
    // ── Team RVM ESS (1C: requests, leave, approvals) ─────────────────────
    ..registerFactory<RequestsBloc>(() => RequestsBloc(getIt()))
    ..registerFactory<ApprovalsBloc>(() => ApprovalsBloc(getIt()))
    // ── Team RVM ESS (1D: notifications) ─────────────────────────────────
    ..registerFactory<NotificationsBloc>(() => NotificationsBloc(getIt()))
    // ── Team RVM ESS (2A: the Wall) ──────────────────────────────────────
    ..registerFactory<WallBloc>(() => WallBloc(getIt()))
    // ── Team RVM ESS (2B: Helpdesk) ───────────────────────────────────────
    ..registerFactory<HelpdeskBloc>(() => HelpdeskBloc(getIt()))
    // Mark screen is per (batch, date) — resolve with param1=batchId, param2=date.
    ..registerFactoryParam<MarkAttendanceBloc, String, DateTime>(
        (batchId, date) =>
            MarkAttendanceBloc(getIt(), batchId: batchId, date: date));
}

/// D5: register this phone for push. A real token exists only once the Firebase project is
/// configured (ADR-0016); until then the backend logs push instead of sending it. Pass a token
/// today with `--dart-define=FCM_TOKEN=...`, or call this from the Firebase setup later.
Future<void> registerPushToken(String token) async {
  try {
    final installId = await getIt<AuthSession>().installId();
    await getIt<EssRepository>().registerPushDevice(
      token: token,
      deviceLabel: 'Android',
      installId: installId,
    );
  } catch (_) {
    // Best effort, unawaited at launch: a refused or offline registration must
    // never surface on the splash or as an uncaught zone error.
  }
}

String _today() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _monthStart() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-01';
}

import 'package:core_auth/core_auth.dart';
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

import 'datasources/accounts_remote_data_source.dart';
import 'datasources/activities_remote_data_source.dart';
import 'datasources/admissions_remote_data_source.dart';
import 'datasources/alerts_remote_data_source.dart';
import 'datasources/scheduling_remote_data_source.dart';
import 'datasources/announcements_remote_data_source.dart';
import 'datasources/allotment_remote_data_source.dart';
import 'datasources/attendance_remote_data_source.dart';
import 'datasources/ceo_remote_data_source.dart';
import 'datasources/certificates_remote_data_source.dart';
import 'datasources/courses_remote_data_source.dart';
import 'datasources/skills_remote_data_source.dart';
import 'datasources/faculty_remote_data_source.dart';
import 'datasources/followups_remote_data_source.dart';
import 'datasources/intake_remote_data_source.dart';
import 'datasources/auth_remote_data_source.dart';
import 'datasources/batches_remote_data_source.dart';
import 'datasources/students_remote_data_source.dart';
import 'datasources/career_remote_data_source.dart';
import 'datasources/chat_remote_data_source.dart';
import 'datasources/dashboard_remote_data_source.dart';
import 'datasources/feedback_remote_data_source.dart';
import 'datasources/jobs_remote_data_source.dart';
import 'datasources/notifications_remote_data_source.dart';
import 'datasources/public_remote_data_source.dart';
import 'datasources/scheduler_remote_data_source.dart';
import 'datasources/staff_auth_remote_data_source.dart';
import 'datasources/substitution_remote_data_source.dart';
import 'datasources/support_remote_data_source.dart';
import 'datasources/tickets_remote_data_source.dart';
import 'datasources/users_remote_data_source.dart';
import 'repositories/accounts_repository.dart';
import 'repositories/activities_repository.dart';
import 'repositories/admissions_repository.dart';
import 'repositories/alerts_repository.dart';
import 'repositories/scheduling_repository.dart';
import 'repositories/announcements_repository.dart';
import 'repositories/allotment_repository.dart';
import 'repositories/attendance_repository.dart';
import 'repositories/ceo_repository.dart';
import 'repositories/certificates_repository.dart';
import 'repositories/courses_repository.dart';
import 'repositories/skills_repository.dart';
import 'repositories/faculty_repository.dart';
import 'repositories/followups_repository.dart';
import 'repositories/intake_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/batches_repository.dart';
import 'repositories/students_repository.dart';
import 'repositories/career_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/dashboard_repository.dart';
import 'repositories/feedback_repository.dart';
import 'repositories/jobs_repository.dart';
import 'repositories/notifications_repository.dart';
import 'repositories/public_repository.dart';
import 'repositories/scheduler_repository.dart';
import 'repositories/staff_auth_repository.dart';
import 'repositories/substitution_repository.dart';
import 'repositories/support_repository.dart';
import 'repositories/tickets_repository.dart';
import 'repositories/users_repository.dart';

/// Assembles the whole data layer from its inputs, so apps register only the
/// repositories in get_it and never touch dio directly (dio stays inside the
/// data layer). Reused by every RVM app.
class DataModule {
  DataModule({
    required ApiEnvironment env,
    required AuthSession session,
    required this.connectivity,
    bool logging = false,
  })  : _schedulerDio = DioFactory.scheduler(env: env, tokens: session, logging: logging),
        _jobPortalDio = DioFactory.jobPortal(env: env, cookieJar: session.cookieJar, logging: logging);

  final ConnectivityService connectivity;
  final Dio _schedulerDio;
  final Dio _jobPortalDio;

  late final AuthRepository authRepository = AuthRepository(
    remote: AuthRemoteDataSource(_jobPortalDio),
    connectivity: connectivity,
  );

  late final JobsRepository jobsRepository = JobsRepository(
    remote: JobsRemoteDataSource(_jobPortalDio),
    connectivity: connectivity,
  );

  late final SchedulerRepository schedulerRepository = SchedulerRepository(
    remote: SchedulerRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff (Scheduler) auth — username/password/location → JWT.
  late final StaffAuthRepository staffAuthRepository = StaffAuthRepository(
    remote: StaffAuthRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Candidate notifications (JobPortal).
  late final NotificationsRepository notificationsRepository = NotificationsRepository(
    remote: NotificationsRemoteDataSource(_jobPortalDio),
    connectivity: connectivity,
  );

  /// Candidate support tickets (JobPortal).
  late final SupportRepository supportRepository = SupportRepository(
    remote: SupportRemoteDataSource(_jobPortalDio),
    connectivity: connectivity,
  );

  /// Public companies browse (JobPortal, unauthenticated).
  late final PublicRepository publicRepository = PublicRepository(
    remote: PublicRemoteDataSource(_jobPortalDio),
    connectivity: connectivity,
  );

  /// Candidate career profile — work-experience stack + skill autocomplete +
  /// resume/avatar/certification uploads (JobPortal).
  late final CareerRepository careerRepository = CareerRepository(
    remote: CareerRemoteDataSource(_jobPortalDio),
    connectivity: connectivity,
  );

  /// App feedback (JobPortal).
  late final FeedbackRepository feedbackRepository = FeedbackRepository(
    remote: FeedbackRemoteDataSource(_jobPortalDio),
    connectivity: connectivity,
  );

  /// Candidate ↔ admin support chat (JobPortal).
  late final ChatRepository chatRepository = ChatRepository(
    remote: ChatRemoteDataSource(_jobPortalDio),
    connectivity: connectivity,
  );

  /// Staff dashboard KPIs (Scheduler).
  late final DashboardRepository dashboardRepository = DashboardRepository(
    remote: DashboardRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff attendance — mark, reports, pending-remarks queue (Scheduler).
  late final AttendanceRepository attendanceRepository = AttendanceRepository(
    remote: AttendanceRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff batch console — list/CRUD/roster + active-students KPI (Scheduler).
  late final BatchesRepository batchesRepository = BatchesRepository(
    remote: BatchesRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff student master — list/CRUD + transfer/defaulter/hold (Scheduler).
  late final StudentsRepository studentsRepository = StudentsRepository(
    remote: StudentsRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff admissions — list/detail + dropout/reactivate/undertaking (Scheduler).
  late final AdmissionsRepository admissionsRepository = AdmissionsRepository(
    remote: AdmissionsRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff accounts / finance — ledger, payments, adjustments (Scheduler).
  late final AccountsRepository accountsRepository = AccountsRepository(
    remote: AccountsRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff batch-allotment — worklist, follow-ups, red-flag tracking (Scheduler).
  late final AllotmentRepository allotmentRepository = AllotmentRepository(
    remote: AllotmentRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff follow-up task management — worklist, staff report, logs (Scheduler).
  late final FollowUpsRepository followUpsRepository = FollowUpsRepository(
    remote: FollowUpsRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff faculty / HR — roster, metrics, CRUD (Scheduler).
  late final FacultyRepository facultyRepository = FacultyRepository(
    remote: FacultyRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff faculty substitution — temporary subs + reassign + merge (Scheduler).
  late final SubstitutionRepository substitutionRepository = SubstitutionRepository(
    remote: SubstitutionRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff support-ticket console — triage, chat, reopen/delete (Scheduler).
  late final TicketsRepository ticketsRepository = TicketsRepository(
    remote: TicketsRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff announcements — branch-scoped list + compose/delete (Scheduler).
  late final AnnouncementsRepository announcementsRepository = AnnouncementsRepository(
    remote: AnnouncementsRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff certificate catalog — list + CRUD (Scheduler, admin-gated writes).
  late final CertificatesRepository certificatesRepository = CertificatesRepository(
    remote: CertificatesRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff skill catalog — branch-scoped list + CRUD (Scheduler).
  late final SkillsRepository skillsRepository = SkillsRepository(
    remote: SkillsRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff course catalog — list/detail(+books)/delete + deferred create/update.
  late final CoursesRepository coursesRepository = CoursesRepository(
    remote: CoursesRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff admission-intake worklist — list + prefill + finalize (Scheduler).
  late final IntakeRepository intakeRepository = IntakeRepository(
    remote: IntakeRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff pending alerts — missing-remark worklist + resolve (Scheduler).
  late final AlertsRepository alertsRepository = AlertsRepository(
    remote: AlertsRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff recent-activity feed (Scheduler).
  late final ActivitiesRepository activitiesRepository = ActivitiesRepository(
    remote: ActivitiesRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff faculty-scheduling helpers — free slots + suggest faculty (Scheduler).
  late final SchedulingRepository schedulingRepository = SchedulingRepository(
    remote: SchedulingRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// Staff user provisioning — list/create/update/delete/role + reset-password.
  late final UsersRepository usersRepository = UsersRepository(
    remote: UsersRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );

  /// CEO command centre — dashboard / trends / collections / faculty attendance.
  late final CeoRepository ceoRepository = CeoRepository(
    remote: CeoRemoteDataSource(_schedulerDio),
    connectivity: connectivity,
  );
}

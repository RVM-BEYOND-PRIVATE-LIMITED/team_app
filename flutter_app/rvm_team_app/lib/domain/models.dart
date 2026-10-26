import 'package:domain/domain.dart';
import 'package:equatable/equatable.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Small, typed models for the endpoints the Scheduler backend serves today.
// Parsed defensively from JSON so a backend tweak cannot crash a screen.
// ─────────────────────────────────────────────────────────────────────────────

int? _int(dynamic v) =>
    v == null ? null : (v is int ? v : int.tryParse(v.toString()));
String? _str(dynamic v) => v?.toString();
bool _bool(dynamic v, {bool fallback = false}) =>
    v == null ? fallback : (v is bool ? v : v.toString() == 'true');
DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString());

/// Password accepted on a 2FA account: a code was emailed; a token comes after
/// `POST /api/users/login/verify`.
class TeamTwoFactorChallenge extends Equatable {
  const TeamTwoFactorChallenge({
    required this.challengeId,
    this.sentTo,
    this.expiresAt,
    this.locationName,
  });

  final String challengeId;
  final String? sentTo;
  final DateTime? expiresAt;
  final String? locationName;

  factory TeamTwoFactorChallenge.fromJson(Map<String, dynamic> json) =>
      TeamTwoFactorChallenge(
        challengeId: _str(json['challenge_id']) ?? '',
        sentTo: _str(json['sent_to']),
        expiresAt: _date(json['expires_at']),
        locationName: _str(json['location_name']),
      );

  @override
  List<Object?> get props => [challengeId, sentTo, expiresAt, locationName];
}

/// Result of a login attempt: a session, or a 2FA challenge.
sealed class TeamLoginOutcome {
  const TeamLoginOutcome();
}

class TeamSignedIn extends TeamLoginOutcome {
  const TeamSignedIn({required this.token, required this.identity});
  final String token;
  final StaffIdentity identity;
}

class TeamTwoFactorRequired extends TeamLoginOutcome {
  const TeamTwoFactorRequired(this.challenge);
  final TeamTwoFactorChallenge challenge;
}

/// `GET /api/me` — the caller's own account.
class TeamProfile extends Equatable {
  const TeamProfile({
    required this.id,
    required this.username,
    required this.role,
    this.locationId,
    this.phoneNumber,
    this.email,
    this.emailVerified = false,
    this.twoFactorEnabled = false,
    this.passwordChangedAt,
    this.photoUrl,
  });

  final String id;
  final String username;
  final String role;
  final int? locationId;
  final String? phoneNumber;
  final String? email;
  final bool emailVerified;
  final bool twoFactorEnabled;
  final DateTime? passwordChangedAt;
  final String? photoUrl;

  factory TeamProfile.fromJson(Map<String, dynamic> json) => TeamProfile(
        id: _str(json['id']) ?? '',
        username: _str(json['username']) ?? '',
        role: _str(json['role']) ?? '',
        locationId: _int(json['location_id']),
        phoneNumber: _str(json['phone_number']),
        email: _str(json['email']),
        emailVerified: _bool(json['email_verified']),
        twoFactorEnabled: _bool(json['two_factor_enabled']),
        passwordChangedAt: _date(json['password_changed_at']),
        photoUrl: _str(json['photo_url']),
      );

  @override
  List<Object?> get props => [
        id,
        username,
        role,
        locationId,
        phoneNumber,
        email,
        emailVerified,
        twoFactorEnabled,
        passwordChangedAt,
        photoUrl
      ];
}

/// One row of `GET /api/me/security-events`.
class SecurityEvent extends Equatable {
  const SecurityEvent(
      {required this.id, required this.event, this.ip, this.createdAt});

  final String id;
  final String event;
  final String? ip;
  final DateTime? createdAt;

  factory SecurityEvent.fromJson(Map<String, dynamic> json) => SecurityEvent(
        id: _str(json['id']) ?? '',
        event: _str(json['event']) ?? '',
        ip: _str(json['ip']),
        createdAt: _date(json['created_at']),
      );

  @override
  List<Object?> get props => [id, event, ip, createdAt];
}

/// A priority task (`GET /api/priority-tasks/inbox`).
class PriorityTask extends Equatable {
  const PriorityTask({
    required this.id,
    required this.title,
    this.notes,
    this.priority = 'high',
    this.status = 'open',
    this.taskDate,
    this.dueDate,
    this.locationName,
    this.assignedByName,
    this.assignedByRole,
    this.progressNote,
    this.cancelReason,
    this.read = false,
    this.isToday = false,
    this.overdue = false,
  });

  final String id;
  final String title;
  final String? notes;
  final String priority;
  final String status;
  final String? taskDate;
  final String? dueDate;
  final String? locationName;
  final String? assignedByName;
  final String? assignedByRole;
  final String? progressNote;
  final String? cancelReason;
  final bool read;
  final bool isToday;
  final bool overdue;

  bool get isDone => status == 'done';

  factory PriorityTask.fromJson(Map<String, dynamic> json) => PriorityTask(
        id: _str(json['id']) ?? '',
        title: _str(json['title']) ?? '',
        notes: _str(json['notes']),
        priority: _str(json['priority']) ?? 'high',
        status: _str(json['status']) ?? 'open',
        taskDate: _str(json['task_date']),
        dueDate: _str(json['due_date']),
        locationName: _str(json['location_name']),
        assignedByName: _str(json['assigned_by_name']),
        assignedByRole: _str(json['assigned_by_role']),
        progressNote: _str(json['progress_note']),
        cancelReason: _str(json['cancel_reason']),
        read: _bool(json['read']),
        isToday: _bool(json['is_today']),
        overdue: _bool(json['overdue']),
      );

  @override
  List<Object?> get props => [
        id,
        title,
        notes,
        priority,
        status,
        taskDate,
        dueDate,
        locationName,
        assignedByName,
        read,
        isToday,
        overdue
      ];
}

/// The whole inbox reply, with its counters.
class PriorityInbox extends Equatable {
  const PriorityInbox({
    required this.tasks,
    this.today,
    this.unread = 0,
    this.outstanding = 0,
    this.receivesTasks = false,
  });

  final List<PriorityTask> tasks;
  final String? today;
  final int unread;
  final int outstanding;
  final bool receivesTasks;

  factory PriorityInbox.fromJson(Map<String, dynamic> json) => PriorityInbox(
        tasks: ((json['tasks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PriorityTask.fromJson(e.cast<String, dynamic>()))
            .toList(),
        today: _str(json['today']),
        unread: _int(json['unread']) ?? 0,
        outstanding: _int(json['outstanding']) ?? 0,
        receivesTasks: _bool(json['receives_tasks']),
      );

  @override
  List<Object?> get props => [tasks, today, unread, outstanding, receivesTasks];
}

/// A batch (`GET /api/batches`) — the fields the app needs.
class TeamBatch extends Equatable {
  const TeamBatch({
    required this.id,
    required this.name,
    this.startDate,
    this.endDate,
    this.startTime,
    this.endTime,
    this.daysOfWeek = const [],
    this.schedule,
    this.scheduleDays = const [],
    this.facultyName,
    this.skillName,
    this.students = 0,
    this.joinedCount = 0,
    this.status,
    this.substituted = false,
  });

  final String id;
  final String name;
  final String? startDate;
  final String? endDate;
  final String? startTime;
  final String? endTime;
  final List<String> daysOfWeek;
  final String? schedule;

  /// `batches.schedule` is an integer[] (1 = Monday). The design shows it as
  /// the "Class roll" chips.
  final List<int> scheduleDays;
  final String? facultyName;
  final String? skillName;
  final int students;
  final int joinedCount;
  final String? status;
  final bool substituted;

  factory TeamBatch.fromJson(Map<String, dynamic> json) {
    final faculty = json['faculty'];
    final skill = json['skill'];
    final days = json['days_of_week'];
    return TeamBatch(
      id: _str(json['id']) ?? '',
      name: _str(json['name']) ?? 'Batch',
      startDate: _str(json['start_date']),
      endDate: _str(json['end_date']),
      startTime: _str(json['start_time']),
      endTime: _str(json['end_time']),
      daysOfWeek: days is List
          ? days.map((e) => e.toString()).toList(growable: false)
          : const [],
      schedule: _str(json['schedule']),
      scheduleDays: () {
        final raw = json['schedule'];
        if (raw is List) {
          return raw
              .map((e) => e is int ? e : int.tryParse(e.toString()))
              .whereType<int>()
              .toList(growable: false);
        }
        final text = raw?.toString() ?? '';
        return RegExp(r'\d+')
            .allMatches(text)
            .map((m) => int.parse(m.group(0)!))
            .toList(growable: false);
      }(),
      facultyName: faculty is Map ? _str(faculty['name']) : null,
      skillName: skill is Map ? _str(skill['name']) : null,
      students: _int(json['students']) ?? 0,
      joinedCount: _int(json['joined_count']) ?? 0,
      status: _str(json['status']),
      substituted: _bool(json['isSubstituted']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        startDate,
        endDate,
        startTime,
        endTime,
        daysOfWeek,
        schedule,
        scheduleDays,
        facultyName,
        skillName,
        students,
        status
      ];
}

/// A branch announcement (`GET /api/announcements`).
class TeamAnnouncement extends Equatable {
  const TeamAnnouncement({
    required this.id,
    required this.title,
    required this.message,
    this.scope,
    this.batchName,
    this.createdAt,
  });

  final String id;
  final String title;
  final String message;
  final String? scope;
  final String? batchName;
  final DateTime? createdAt;

  factory TeamAnnouncement.fromJson(Map<String, dynamic> json) {
    final batch = json['batch'];
    return TeamAnnouncement(
      id: _str(json['id']) ?? '',
      title: _str(json['title']) ?? '',
      message: _str(json['message']) ?? '',
      scope: _str(json['scope']),
      batchName: batch is Map ? _str(batch['name']) : null,
      createdAt: _date(json['created_at']),
    );
  }

  @override
  List<Object?> get props => [id, title, message, scope, batchName, createdAt];
}

/// An interview round for the panel member (`GET /api/interviews/mine/upcoming`).
class InterviewRound extends Equatable {
  const InterviewRound({
    required this.id,
    this.roundName,
    this.scheduledAt,
    this.mode,
    this.meetingLink,
    this.status,
    this.candidateName,
    this.position,
  });

  final String id;
  final String? roundName;
  final DateTime? scheduledAt;
  final String? mode;
  final String? meetingLink;
  final String? status;
  final String? candidateName;
  final String? position;

  factory InterviewRound.fromJson(Map<String, dynamic> json) => InterviewRound(
        id: _str(json['id']) ?? '',
        roundName: _str(json['round_name']),
        scheduledAt: _date(json['scheduled_at']),
        mode: _str(json['mode']),
        meetingLink: _str(json['meeting_link']),
        status: _str(json['status']),
        candidateName: _str(json['candidate_name']),
        position: _str(json['position']),
      );

  @override
  List<Object?> get props =>
      [id, roundName, scheduledAt, mode, status, candidateName, position];
}

// ─────────────────────────────────────────────────────────────────────────────
// Faculty Development (HOD) + faculty indicators
// ─────────────────────────────────────────────────────────────────────────────

/// One faculty option for the HOD forms (`GET /api/hod/roster/faculty-options`).
class FacultyOption extends Equatable {
  const FacultyOption({required this.id, required this.name});

  final String id;
  final String name;

  factory FacultyOption.fromJson(Map<String, dynamic> json) => FacultyOption(
        id: _str(json['id']) ?? _str(json['faculty_id']) ?? '',
        name: _str(json['name']) ?? _str(json['faculty_name']) ?? 'Faculty',
      );

  @override
  List<Object?> get props => [id, name];
}

/// One to-do item in the HOD overview's action list.
class HodAction extends Equatable {
  const HodAction({
    required this.key,
    required this.label,
    this.detail,
    this.count = 0,
    this.severity = 'medium',
    this.tab,
  });

  final String key;
  final String label;
  final String? detail;
  final int count;
  final String severity;
  final String? tab;

  factory HodAction.fromJson(Map<String, dynamic> json) => HodAction(
        key: _str(json['key']) ?? '',
        label: _str(json['label']) ?? '',
        detail: _str(json['detail']),
        count: _int(json['count']) ?? 0,
        severity: _str(json['severity']) ?? 'medium',
        tab: _str(json['tab']),
      );

  @override
  List<Object?> get props => [key, label, detail, count, severity, tab];
}

/// `GET /api/hod/overview` — the Faculty Development to-do list for a month.
class HodOverview extends Equatable {
  const HodOverview({this.month, this.domain, this.actions = const []});

  final String? month;
  final String? domain;
  final List<HodAction> actions;

  factory HodOverview.fromJson(Map<String, dynamic> json) => HodOverview(
        month: _str(json['month']),
        domain: _str(json['domain']),
        actions: ((json['actions'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => HodAction.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  @override
  List<Object?> get props => [month, domain, actions];
}

/// One HOD interview row (`GET /api/hod/interviews` — `interview_log`).
class HodInterview extends Equatable {
  const HodInterview({
    required this.id,
    this.candidateName,
    this.position,
    this.interviewDate,
    this.verdict,
    this.feedback,
    this.slaBreached = false,
    this.turnaroundDays,
  });

  final String id;
  final String? candidateName;
  final String? position;
  final String? interviewDate;
  final String? verdict;
  final String? feedback;
  final bool slaBreached;
  final int? turnaroundDays;

  bool get pending => verdict == null || verdict!.isEmpty;

  factory HodInterview.fromJson(Map<String, dynamic> json) => HodInterview(
        id: _str(json['id']) ?? '',
        candidateName: _str(json['candidate_name']) ?? _str(json['candidate']),
        position: _str(json['position']) ?? _str(json['role']),
        interviewDate: _str(json['interview_date']),
        verdict: _str(json['hod_verdict']),
        feedback: _str(json['hod_feedback']),
        slaBreached: _bool(json['sla_breached']),
        turnaroundDays: _int(json['turnaround_days']),
      );

  @override
  List<Object?> get props => [
        id,
        candidateName,
        position,
        interviewDate,
        verdict,
        feedback,
        slaBreached
      ];
}

/// A per-batch row of the faculty indicators report.
class FacultyBatchReport extends Equatable {
  const FacultyBatchReport({
    required this.batchId,
    required this.batchName,
    this.status,
    this.studentCount = 0,
    this.expectedSessions = 0,
    this.markedSessions = 0,
    this.attendancePercentage,
    this.missingSessions = 0,
    this.isComplete = true,
  });

  final String batchId;
  final String batchName;
  final String? status;
  final int studentCount;
  final int expectedSessions;
  final int markedSessions;
  final double? attendancePercentage;
  final int missingSessions;
  final bool isComplete;

  factory FacultyBatchReport.fromJson(Map<String, dynamic> json) {
    final compliance = json['compliance'];
    final c = compliance is Map
        ? compliance.cast<String, dynamic>()
        : const <String, dynamic>{};
    final missing = c['missing_attendance_dates'];
    return FacultyBatchReport(
      batchId: _str(json['batch_id']) ?? '',
      batchName: _str(json['batch_name']) ?? 'Batch',
      status: _str(json['status']),
      studentCount: _int(json['student_count']) ?? 0,
      expectedSessions: _int(json['expected_sessions']) ?? 0,
      markedSessions: _int(json['marked_sessions']) ?? 0,
      attendancePercentage: (json['attendance_percentage'] is num)
          ? (json['attendance_percentage'] as num).toDouble()
          : double.tryParse('${json['attendance_percentage']}'),
      missingSessions: missing is List ? missing.length : 0,
      isComplete: _bool(c['is_complete'], fallback: true),
    );
  }

  @override
  List<Object?> get props => [
        batchId,
        batchName,
        status,
        studentCount,
        expectedSessions,
        markedSessions,
        attendancePercentage
      ];
}

/// `GET /api/attendance/reports/faculty/:id` — the faculty indicators card.
class FacultyReport extends Equatable {
  const FacultyReport({
    required this.facultyId,
    this.facultyName,
    this.percentage,
    this.batches = const [],
  });

  final String facultyId;
  final String? facultyName;
  final double? percentage;
  final List<FacultyBatchReport> batches;

  int get missingSessions => batches.fold(0, (n, b) => n + b.missingSessions);

  factory FacultyReport.fromJson(Map<String, dynamic> json) => FacultyReport(
        facultyId: _str(json['faculty_id']) ?? '',
        facultyName: _str(json['faculty_name']),
        percentage: (json['faculty_attendance_percentage'] is num)
            ? (json['faculty_attendance_percentage'] as num).toDouble()
            : double.tryParse('${json['faculty_attendance_percentage']}'),
        batches: ((json['batches'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => FacultyBatchReport.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  @override
  List<Object?> get props => [facultyId, facultyName, percentage, batches];
}

/// The Scheduler's attendance sign-in result (`POST /hr/my-attendance/password-login`
/// and `/otp/verify`) — a 30-day attendance session for staff with no portal login.
class AttendanceLoginResult {
  const AttendanceLoginResult({
    required this.token,
    this.expiresInDays = 30,
    this.employeeName,
    this.passwordSet = true,
    this.temporary = false,
  });

  final String token;
  final int expiresInDays;
  final String? employeeName;

  /// False when the login has no password yet — offer to set one.
  final bool passwordSet;

  /// True while the password is still the one HR gave (must be changed before punching).
  final bool temporary;

  factory AttendanceLoginResult.fromJson(Map<String, dynamic> json) =>
      AttendanceLoginResult(
        token: _str(json['token']) ?? '',
        expiresInDays: (json['expires_in_days'] is num)
            ? (json['expires_in_days'] as num).toInt()
            : 30,
        employeeName: json['employee'] is Map
            ? _str((json['employee'] as Map)['full_name'])
            : null,
        passwordSet: json['password_set'] == true,
        temporary: json['temporary'] == true,
      );
}

/// A sign-in code that was sent (`POST /hr/my-attendance/otp/request`).
class AttendanceCodeSent {
  const AttendanceCodeSent({
    required this.challengeId,
    this.channel,
    this.sentTo,
    this.expiresAt,
    this.ttlMinutes = 10,
    this.sandbox = false,
  });

  final String challengeId;
  final String? channel; // sms | email
  final String? sentTo; // masked
  final DateTime? expiresAt;
  final int ttlMinutes;
  final bool sandbox;

  factory AttendanceCodeSent.fromJson(Map<String, dynamic> json) =>
      AttendanceCodeSent(
        challengeId: _str(json['challenge_id']) ?? '',
        channel: _str(json['channel']),
        sentTo: _str(json['sent_to']),
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.tryParse('${json['expires_at']}'),
        ttlMinutes: (json['ttl_minutes'] is num)
            ? (json['ttl_minutes'] as num).toInt()
            : 10,
        sandbox: json['sandbox'] == true,
      );
}

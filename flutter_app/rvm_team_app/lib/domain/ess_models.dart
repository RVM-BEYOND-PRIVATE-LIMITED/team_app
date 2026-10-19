import 'package:equatable/equatable.dart';

/// Models for the Team RVM ESS backend (`team_app`, `/api/ess`), shaped by
/// `packages/contracts/openapi.yaml` (v0.2.1). Kept apart from the Scheduler
/// `models.dart` so the two backends never blur.

Map<String, dynamic>? _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : null;
String? _str(dynamic v) => v?.toString();
int? _int(dynamic v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
bool _bool(dynamic v) => v == true;
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList(growable: false) : const [];

/// `GET /health`.
class EssHealth extends Equatable {
  const EssHealth({
    required this.ok,
    this.serverTime,
    this.version,
    this.minAppVersion,
    this.latestAppVersion,
    this.db,
  });

  final bool ok;
  final DateTime? serverTime;
  final String? version;
  final String? minAppVersion;
  final String? latestAppVersion;
  final String? db;

  bool get dbReachable => db == 'ok';

  factory EssHealth.fromJson(Map<String, dynamic> j) => EssHealth(
        ok: _bool(j['ok']),
        serverTime: _date(j['server_time']),
        version: _str(j['version']),
        minAppVersion: _str(j['min_app_version']),
        latestAppVersion: _str(j['latest_app_version']),
        db: _str(j['db']),
      );

  @override
  List<Object?> get props => [ok, version, minAppVersion, latestAppVersion, db];
}

class EssOrganizationRef extends Equatable {
  const EssOrganizationRef({required this.id, required this.name});
  final String id;
  final String name;
  factory EssOrganizationRef.fromJson(Map<String, dynamic> j) =>
      EssOrganizationRef(id: _str(j['id']) ?? '', name: _str(j['name']) ?? '');
  @override
  List<Object?> get props => [id, name];
}

class EssManagerRef extends Equatable {
  const EssManagerRef({required this.id, required this.fullName});
  final String id;
  final String fullName;
  factory EssManagerRef.fromJson(Map<String, dynamic> j) =>
      EssManagerRef(id: _str(j['id']) ?? '', fullName: _str(j['full_name']) ?? '');
  @override
  List<Object?> get props => [id, fullName];
}

/// `Employee` schema — the caller's HR record.
class EssEmployee extends Equatable {
  const EssEmployee({
    required this.id,
    required this.fullName,
    this.employeeCode,
    this.designation,
    required this.employmentStatus,
    this.branch,
    this.department,
    this.manager,
  });

  final String id;
  final String fullName;
  final String? employeeCode;
  final String? designation;
  final String employmentStatus;
  final EssOrganizationRef? branch;
  final EssOrganizationRef? department;
  final EssManagerRef? manager;

  factory EssEmployee.fromJson(Map<String, dynamic> j) => EssEmployee(
        id: _str(j['id']) ?? '',
        fullName: _str(j['full_name']) ?? '',
        employeeCode: _str(j['employee_code']),
        designation: _str(j['designation']),
        employmentStatus: _str(j['employment_status']) ?? 'active',
        branch: _map(j['branch']) == null ? null : EssOrganizationRef.fromJson(_map(j['branch'])!),
        department:
            _map(j['department']) == null ? null : EssOrganizationRef.fromJson(_map(j['department'])!),
        manager: _map(j['manager']) == null ? null : EssManagerRef.fromJson(_map(j['manager'])!),
      );

  @override
  List<Object?> get props => [id, fullName, employeeCode, designation, employmentStatus];
}

/// `Login` schema — which token the request carried.
class EssLogin extends Equatable {
  const EssLogin({required this.kind, this.role, this.userId});
  final String kind;
  final String? role;
  final String? userId;

  bool get isEmployee => kind == 'attendance' || role != null;

  factory EssLogin.fromJson(Map<String, dynamic> j) => EssLogin(
        kind: _str(j['kind']) ?? 'portal',
        role: _str(j['role']),
        userId: _str(j['user_id']),
      );

  @override
  List<Object?> get props => [kind, role, userId];
}

class EssMe extends Equatable {
  const EssMe({required this.employee, required this.login});
  final EssEmployee employee;
  final EssLogin login;
  factory EssMe.fromJson(Map<String, dynamic> j) => EssMe(
        employee: EssEmployee.fromJson(_map(j['employee']) ?? const {}),
        login: EssLogin.fromJson(_map(j['login']) ?? const {}),
      );
  @override
  List<Object?> get props => [employee, login];
}

/// `Capabilities` schema — what the app may show this person.
class EssCapabilities extends Equatable {
  const EssCapabilities({
    required this.tabs,
    required this.sectionTime,
    required this.sectionHelpdesk,
    required this.sectionDocuments,
    required this.sectionProfile,
    required this.sectionWork,
    required this.hasReports,
    required this.directReports,
    required this.approvalsOwnReports,
    required this.approvalsAnyRequest,
    required this.approvalRequestTypes,
    required this.hrScope,
    required this.wallPost,
    required this.wallAnnounce,
    required this.wallModerate,
    required this.pushEnabled,
    required this.integrityRequired,
  });

  final List<String> tabs;
  final bool sectionTime;
  final bool sectionHelpdesk;
  final bool sectionDocuments;
  final bool sectionProfile;
  final bool sectionWork;
  final bool hasReports;
  final int directReports;
  final bool approvalsOwnReports;
  final bool approvalsAnyRequest;
  final List<String> approvalRequestTypes;
  final List<String> hrScope;
  final bool wallPost;
  final bool wallAnnounce;
  final bool wallModerate;
  final bool pushEnabled;
  final bool integrityRequired;

  bool get canSeeHrTools => hrScope.isNotEmpty || approvalsAnyRequest;

  factory EssCapabilities.fromJson(Map<String, dynamic> j) {
    final sections = _map(j['sections']) ?? const {};
    final team = _map(j['team']) ?? const {};
    final approvals = _map(j['approvals']) ?? const {};
    final wall = _map(j['wall']) ?? const {};
    final push = _map(j['push']) ?? const {};
    final integrity = _map(j['integrity']) ?? const {};
    return EssCapabilities(
      tabs: _strings(j['tabs']),
      sectionTime: _bool(sections['time']),
      sectionHelpdesk: _bool(sections['helpdesk']),
      sectionDocuments: _bool(sections['documents']),
      sectionProfile: _bool(sections['profile']),
      sectionWork: _bool(sections['work']),
      hasReports: _bool(team['has_reports']),
      directReports: _int(team['direct_reports']) ?? 0,
      approvalsOwnReports: _bool(approvals['own_reports']),
      approvalsAnyRequest: _bool(approvals['any_request']),
      approvalRequestTypes: _strings(approvals['request_types']),
      hrScope: _strings(approvals['hr_scope']),
      wallPost: _bool(wall['post']),
      wallAnnounce: _bool(wall['announce']),
      wallModerate: _bool(wall['moderate']),
      pushEnabled: _bool(push['enabled']),
      integrityRequired: _bool(integrity['required']),
    );
  }

  @override
  List<Object?> get props => [tabs, sectionTime, sectionWork, directReports, hrScope, wallPost];
}

/// `PersonalDetails` schema (E9).
class PersonalDetails extends Equatable {
  const PersonalDetails({
    this.dateOfBirth,
    this.bloodGroup,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.pincode,
    this.emergencyName,
    this.emergencyRelation,
    this.emergencyPhone,
    this.updatedAt,
    this.updatedByName,
  });

  final String? dateOfBirth;
  final String? bloodGroup;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? pincode;
  final String? emergencyName;
  final String? emergencyRelation;
  final String? emergencyPhone;
  final DateTime? updatedAt;
  final String? updatedByName;

  factory PersonalDetails.fromJson(Map<String, dynamic> j) => PersonalDetails(
        dateOfBirth: _str(j['date_of_birth']),
        bloodGroup: _str(j['blood_group']),
        addressLine1: _str(j['address_line1']),
        addressLine2: _str(j['address_line2']),
        city: _str(j['city']),
        state: _str(j['state']),
        pincode: _str(j['pincode']),
        emergencyName: _str(j['emergency_name']),
        emergencyRelation: _str(j['emergency_relation']),
        emergencyPhone: _str(j['emergency_phone']),
        updatedAt: _date(j['updated_at']),
        updatedByName: _str(j['updated_by_name']),
      );

  String? get addressOneLine {
    final parts = [addressLine1, addressLine2, city, state, pincode]
        .where((p) => p != null && p.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  @override
  List<Object?> get props => [
        dateOfBirth, bloodGroup, addressLine1, addressLine2, city, state, pincode,
        emergencyName, emergencyRelation, emergencyPhone, updatedAt,
      ];
}

/// `EmployeeCard` — who a row is about.
class EmployeeCard extends Equatable {
  const EmployeeCard({required this.id, required this.fullName, this.employeeCode});
  final String id;
  final String fullName;
  final String? employeeCode;
  factory EmployeeCard.fromJson(Map<String, dynamic> j) => EmployeeCard(
        id: _str(j['id']) ?? '',
        fullName: _str(j['full_name']) ?? '',
        employeeCode: _str(j['employee_code']),
      );
  @override
  List<Object?> get props => [id, fullName, employeeCode];
}

class BranchRef extends Equatable {
  const BranchRef({required this.id, required this.name});
  final String id;
  final String name;
  factory BranchRef.fromJson(Map<String, dynamic> j) =>
      BranchRef(id: _str(j['id']) ?? '', name: _str(j['name']) ?? '');
  @override
  List<Object?> get props => [id, name];
}

/// `DataRequest` (owner) / `HrDataRequest` (HR) — one shape, optional extras.
class EssDataRequest extends Equatable {
  const EssDataRequest({
    required this.id,
    required this.kind,
    required this.details,
    required this.status,
    this.createdAt,
    this.resolvedAt,
    this.resolutionNote,
    this.resolvedByName,
    this.employee,
  });

  final String id;
  final String kind; // correct | delete
  final String details;
  final String status; // open | done | rejected
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final String? resolutionNote;
  final String? resolvedByName;
  final EmployeeCard? employee;

  bool get isOpen => status == 'open';

  String get kindLabel => kind == 'delete' ? 'Delete my data' : 'Correct my data';

  factory EssDataRequest.fromJson(Map<String, dynamic> j) => EssDataRequest(
        id: _str(j['id']) ?? '',
        kind: _str(j['kind']) ?? 'correct',
        details: _str(j['details']) ?? '',
        status: _str(j['status']) ?? 'open',
        createdAt: _date(j['created_at']),
        resolvedAt: _date(j['resolved_at']),
        resolutionNote: _str(j['resolution_note']),
        resolvedByName: _str(j['resolved_by_name']),
        employee: _map(j['employee']) == null ? null : EmployeeCard.fromJson(_map(j['employee'])!),
      );

  @override
  List<Object?> get props => [id, kind, status, createdAt, resolutionNote];
}

/// `SignInResolution` — one-field sign-in resolver answer (A5).
class SignInResolution extends Equatable {
  const SignInResolution({required this.kind, this.loginWith, this.locationNames = const [], this.methods = const []});
  final String kind; // portal | attendance | unknown
  final String? loginWith; // as_typed | username_or_phone
  final List<String> locationNames;
  final List<String> methods; // code | password

  factory SignInResolution.fromJson(Map<String, dynamic> j) => SignInResolution(
        kind: _str(j['kind']) ?? 'unknown',
        loginWith: _str(j['login_with']),
        locationNames: _strings(j['location_names']),
        methods: _strings(j['methods']),
      );

  @override
  List<Object?> get props => [kind, loginWith, locationNames, methods];
}

/// `StoredDay` (B1) — the Scheduler's row for one day.
class StoredDay extends Equatable {
  const StoredDay({
    required this.status,
    this.leaveType,
    this.source,
    this.firstIn,
    this.lastOut,
    this.workedMinutes,
    this.lateMinutes,
    this.earlyExitMinutes,
    this.lateCount,
    required this.lateHalfDay,
    required this.lateExcused,
    this.shiftStart,
    this.shiftEnd,
  });

  final String status;
  final String? leaveType;
  final String? source;
  final DateTime? firstIn;
  final DateTime? lastOut;
  final int? workedMinutes;
  final int? lateMinutes;
  final int? earlyExitMinutes;
  final int? lateCount;
  final bool lateHalfDay;
  final bool lateExcused;
  final String? shiftStart;
  final String? shiftEnd;

  factory StoredDay.fromJson(Map<String, dynamic> j) => StoredDay(
        status: _str(j['status']) ?? 'unknown',
        leaveType: _str(j['leave_type']),
        source: _str(j['source']),
        firstIn: _date(j['first_in']),
        lastOut: _date(j['last_out']),
        workedMinutes: _int(j['worked_minutes']),
        lateMinutes: _int(j['late_minutes']),
        earlyExitMinutes: _int(j['early_exit_minutes']),
        lateCount: _int(j['late_count']),
        lateHalfDay: _bool(j['late_half_day']),
        lateExcused: _bool(j['late_excused']),
        shiftStart: _str(j['shift_start']),
        shiftEnd: _str(j['shift_end']),
      );

  @override
  List<Object?> get props => [status, firstIn, lastOut, workedMinutes, lateMinutes];
}

class DayRemark extends Equatable {
  const DayRemark({required this.remarks, this.updatedAt});
  final String remarks;
  final DateTime? updatedAt;
  factory DayRemark.fromJson(Map<String, dynamic> j) =>
      DayRemark(remarks: _str(j['remarks']) ?? '', updatedAt: _date(j['updated_at']));
  @override
  List<Object?> get props => [remarks, updatedAt];
}

class MyRemark extends Equatable {
  const MyRemark({required this.day, required this.remarks, this.updatedAt});
  final String day;
  final String remarks;
  final DateTime? updatedAt;
  factory MyRemark.fromJson(Map<String, dynamic> j) => MyRemark(
        day: _str(j['day']) ?? '',
        remarks: _str(j['remarks']) ?? '',
        updatedAt: _date(j['updated_at']),
      );
  @override
  List<Object?> get props => [day, remarks, updatedAt];
}

/// `AttendanceDay` (B1).
class AttendanceDay extends Equatable {
  const AttendanceDay({
    required this.serverNow,
    required this.date,
    this.day,
    this.note,
    this.hrRemark,
    this.myRemarks = const [],
  });

  final DateTime? serverNow;
  final String date;
  final StoredDay? day;
  final String? note;
  final DayRemark? hrRemark;
  final List<MyRemark> myRemarks;

  factory AttendanceDay.fromJson(Map<String, dynamic> j) => AttendanceDay(
        serverNow: _date(j['server_now']),
        date: _str(j['date']) ?? '',
        day: _map(j['day']) == null ? null : StoredDay.fromJson(_map(j['day'])!),
        note: _str(j['note']),
        hrRemark: _map(j['hr_remark']) == null ? null : DayRemark.fromJson(_map(j['hr_remark'])!),
        myRemarks: j['my_remarks'] is List
            ? (j['my_remarks'] as List)
                .whereType<Map>()
                .map((e) => MyRemark.fromJson(e.cast<String, dynamic>()))
                .toList(growable: false)
            : const [],
      );

  @override
  List<Object?> get props => [date, day, note, hrRemark, myRemarks];
}

/// `MockLocationReport` (B14).
class MockLocationReport extends Equatable {
  const MockLocationReport({
    required this.id,
    this.reportedAt,
    this.kind,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.provider,
    this.appVersion,
    this.installId,
    this.employee,
    this.branch,
  });

  final String id;
  final DateTime? reportedAt;
  final String? kind;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;
  final String? provider;
  final String? appVersion;
  final String? installId;
  final EmployeeCard? employee;
  final BranchRef? branch;

  factory MockLocationReport.fromJson(Map<String, dynamic> j) => MockLocationReport(
        id: _str(j['id']) ?? '',
        reportedAt: _date(j['reported_at']),
        kind: _str(j['kind']),
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        accuracyM: (j['accuracy_m'] as num?)?.toDouble(),
        provider: _str(j['provider']),
        appVersion: _str(j['app_version']),
        installId: _str(j['install_id']),
        employee: _map(j['employee']) == null ? null : EmployeeCard.fromJson(_map(j['employee'])!),
        branch: _map(j['branch']) == null ? null : BranchRef.fromJson(_map(j['branch'])!),
      );

  @override
  List<Object?> get props => [id, reportedAt, kind, latitude, longitude];
}

/// `RegisteredPhone` (B8).
class RegisteredPhone extends Equatable {
  const RegisteredPhone({
    required this.id,
    required this.status,
    this.boundAt,
    this.lastSeenAt,
    this.revokedAt,
    this.revokedByName,
    this.revokeReason,
    this.employee,
    this.branch,
  });

  final String id;
  final String status; // active | revoked
  final DateTime? boundAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;
  final String? revokedByName;
  final String? revokeReason;
  final EmployeeCard? employee;
  final BranchRef? branch;

  bool get isActive => status == 'active';

  factory RegisteredPhone.fromJson(Map<String, dynamic> j) => RegisteredPhone(
        id: _str(j['id']) ?? '',
        status: _str(j['status']) ?? 'active',
        boundAt: _date(j['bound_at']),
        lastSeenAt: _date(j['last_seen_at']),
        revokedAt: _date(j['revoked_at']),
        revokedByName: _str(j['revoked_by_name']),
        revokeReason: _str(j['revoke_reason']),
        employee: _map(j['employee']) == null ? null : EmployeeCard.fromJson(_map(j['employee'])!),
        branch: _map(j['branch']) == null ? null : BranchRef.fromJson(_map(j['branch'])!),
      );

  @override
  List<Object?> get props => [id, status, boundAt, lastSeenAt, revokeReason];
}

/// `SessionSummary` — one kept sign-in (A3).
class TeamSession extends Equatable {
  const TeamSession({
    required this.id,
    this.deviceLabel,
    this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
    required this.current,
  });

  final String id;
  final String? deviceLabel;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
  final bool current;

  factory TeamSession.fromJson(Map<String, dynamic> j) => TeamSession(
        id: _str(j['id']) ?? '',
        deviceLabel: _str(j['device_label']),
        createdAt: _date(j['created_at']),
        lastUsedAt: _date(j['last_used_at']),
        expiresAt: _date(j['expires_at']),
        current: _bool(j['current']),
      );

  @override
  List<Object?> get props => [id, deviceLabel, createdAt, lastUsedAt, expiresAt, current];
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 1E — Me & My Team (routes meProfile.js, meOrg.js, team.js; policy/me.js)
// ═══════════════════════════════════════════════════════════════════════════

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(growable: false)
    : const [];

/// A colleague card shared by the org, directory and team views (E2/E6/E8).
class OrgCard extends Equatable {
  const OrgCard({
    required this.id,
    required this.fullName,
    this.employeeCode,
    this.designation,
    this.department,
    this.branch,
    this.email,
    this.phone,
    this.employmentStatus,
    required this.noticePeriod,
  });

  final String id;
  final String fullName;
  final String? employeeCode;
  final String? designation;
  final BranchRef? department;
  final BranchRef? branch;
  final String? email;
  final String? phone;
  final String? employmentStatus;
  final bool noticePeriod;

  factory OrgCard.fromJson(Map<String, dynamic> j) => OrgCard(
        id: _str(j['id']) ?? '',
        fullName: _str(j['full_name']) ?? '',
        employeeCode: _str(j['employee_code']),
        designation: _str(j['designation']),
        department: _map(j['department']) == null ? null : BranchRef.fromJson(_map(j['department'])!),
        branch: _map(j['branch']) == null ? null : BranchRef.fromJson(_map(j['branch'])!),
        email: _str(j['email']),
        phone: _str(j['phone']),
        employmentStatus: _str(j['employment_status']),
        noticePeriod: _bool(j['notice_period']),
      );

  @override
  List<Object?> get props =>
      [id, fullName, designation, department, branch, email, phone, noticePeriod];
}

/// `GET /me/org`.
class OrgView extends Equatable {
  const OrgView({
    required this.managerChain,
    required this.reportsToCeoNotRecorded,
    required this.peers,
    required this.directReportCount,
    required this.directReports,
    this.department,
    required this.departmentPeople,
  });

  final List<OrgCard> managerChain;
  final bool reportsToCeoNotRecorded;
  final List<OrgCard> peers;
  final int directReportCount;
  final List<OrgCard> directReports;
  final BranchRef? department;
  final List<OrgCard> departmentPeople;

  factory OrgView.fromJson(Map<String, dynamic> j) {
    final dept = _map(j['department']);
    final reports = _map(j['direct_reports']) ?? const {};
    return OrgView(
      managerChain: _maps(j['manager_chain']).map(OrgCard.fromJson).toList(growable: false),
      reportsToCeoNotRecorded: _bool(j['reports_to_ceo_not_recorded']),
      peers: _maps(j['peers']).map(OrgCard.fromJson).toList(growable: false),
      directReportCount: _int(reports['count']) ?? 0,
      directReports: _maps(reports['people']).map(OrgCard.fromJson).toList(growable: false),
      department: dept == null ? null : BranchRef.fromJson(dept),
      departmentPeople:
          dept == null ? const [] : _maps(dept['people']).map(OrgCard.fromJson).toList(growable: false),
    );
  }

  @override
  List<Object?> get props => [managerChain, peers, directReportCount, department];
}

/// `GET /directory`.
class DirectoryPage extends Equatable {
  const DirectoryPage({required this.people, required this.truncated});
  final List<OrgCard> people;
  final bool truncated;
  factory DirectoryPage.fromJson(Map<String, dynamic> j) => DirectoryPage(
        people: _maps(j['people']).map(OrgCard.fromJson).toList(growable: false),
        truncated: _bool(j['truncated']),
      );
  @override
  List<Object?> get props => [people, truncated];
}

/// One row of `GET /team/today`: an [OrgCard] plus the day's state (E6/H4).
class TeamPerson extends Equatable {
  const TeamPerson({required this.card, required this.state, required this.late, this.lateMinutes, this.firstIn, this.lastOut});
  final OrgCard card;
  final String state; // in | done | not_in | on_leave | week_off | holiday
  final bool late;
  final int? lateMinutes;
  final DateTime? firstIn;
  final DateTime? lastOut;

  factory TeamPerson.fromJson(Map<String, dynamic> j) => TeamPerson(
        card: OrgCard.fromJson(j),
        state: _str(j['state']) ?? 'not_in',
        late: _bool(j['late']),
        lateMinutes: _int(j['late_minutes']),
        firstIn: _date(j['first_in']),
        lastOut: _date(j['last_out']),
      );

  @override
  List<Object?> get props => [card, state, late, lateMinutes];
}

/// `GET /team/today`.
class TeamTodayView extends Equatable {
  const TeamTodayView({
    this.scope,
    required this.date,
    required this.filter,
    required this.all,
    required this.notIn,
    required this.late,
    required this.onLeave,
    required this.people,
  });

  final String? scope; // reports | branch | null
  final String date;
  final String filter;
  final int all;
  final int notIn;
  final int late;
  final int onLeave;
  final List<TeamPerson> people;

  bool get hasRoster => scope != null;

  factory TeamTodayView.fromJson(Map<String, dynamic> j) {
    final c = _map(j['counts']) ?? const {};
    return TeamTodayView(
      scope: _str(j['scope']),
      date: _str(j['date']) ?? '',
      filter: _str(j['filter']) ?? 'all',
      all: _int(c['all']) ?? 0,
      notIn: _int(c['not_in']) ?? 0,
      late: _int(c['late']) ?? 0,
      onLeave: _int(c['on_leave']) ?? 0,
      people: _maps(j['people']).map(TeamPerson.fromJson).toList(growable: false),
    );
  }

  @override
  List<Object?> get props => [scope, date, filter, all, notIn, late, onLeave, people];
}

class OffWeekPerson extends Equatable {
  const OffWeekPerson({required this.card, required this.days});
  final OrgCard card;
  final List<String> days;
  factory OffWeekPerson.fromJson(Map<String, dynamic> j) =>
      OffWeekPerson(card: OrgCard.fromJson(j), days: _strings(j['days']));
  @override
  List<Object?> get props => [card, days];
}

/// `GET /team/off-this-week`.
class TeamOffWeek extends Equatable {
  const TeamOffWeek({required this.from, required this.to, this.scope, required this.people});
  final String from;
  final String to;
  final String? scope; // reports | peers | null
  final List<OffWeekPerson> people;

  factory TeamOffWeek.fromJson(Map<String, dynamic> j) {
    final week = _map(j['week']) ?? const {};
    return TeamOffWeek(
      from: _str(week['from']) ?? '',
      to: _str(week['to']) ?? '',
      scope: _str(j['scope']),
      people: _maps(j['people']).map(OffWeekPerson.fromJson).toList(growable: false),
    );
  }

  @override
  List<Object?> get props => [from, to, scope, people];
}

/// `GET /me/profile` — the HR record's Summary/Job plus Personal and the Timeline (E1/E12).
class MyProfileEmployee extends Equatable {
  const MyProfileEmployee({
    required this.id,
    required this.fullName,
    this.employeeCode,
    this.designation,
    this.department,
    this.branch,
    this.manager,
    this.dateOfJoining,
    this.employmentStatus,
    required this.noticePeriod,
    this.email,
    this.phone,
    this.photoUrl,
  });

  final String id;
  final String fullName;
  final String? employeeCode;
  final String? designation;
  final BranchRef? department;
  final BranchRef? branch;
  final EssManagerRef? manager;
  final String? dateOfJoining;
  final String? employmentStatus;
  final bool noticePeriod;
  final String? email;
  final String? phone;
  final String? photoUrl;

  factory MyProfileEmployee.fromJson(Map<String, dynamic> j) => MyProfileEmployee(
        id: _str(j['id']) ?? '',
        fullName: _str(j['full_name']) ?? '',
        employeeCode: _str(j['employee_code']),
        designation: _str(j['designation']),
        department: _map(j['department']) == null ? null : BranchRef.fromJson(_map(j['department'])!),
        branch: _map(j['branch']) == null ? null : BranchRef.fromJson(_map(j['branch'])!),
        manager: _map(j['manager']) == null ? null : EssManagerRef.fromJson(_map(j['manager'])!),
        dateOfJoining: _str(j['date_of_joining']),
        employmentStatus: _str(j['employment_status']),
        noticePeriod: _bool(j['notice_period']),
        email: _str(j['email']),
        phone: _str(j['phone']),
        photoUrl: _str(j['photo_url']),
      );

  @override
  List<Object?> get props => [id, fullName, designation, department, branch, dateOfJoining, noticePeriod, photoUrl];
}

class TimelineEvent extends Equatable {
  const TimelineEvent({required this.id, required this.title, this.at});
  final String id;
  final String title;
  final DateTime? at;
  factory TimelineEvent.fromJson(Map<String, dynamic> j) =>
      TimelineEvent(id: _str(j['id']) ?? '', title: _str(j['title']) ?? '', at: _date(j['at']));
  @override
  List<Object?> get props => [id, title, at];
}

class MyProfile extends Equatable {
  const MyProfile({required this.employee, required this.personal, required this.timeline});
  final MyProfileEmployee employee;
  final PersonalDetails personal;
  final List<TimelineEvent> timeline;
  factory MyProfile.fromJson(Map<String, dynamic> j) => MyProfile(
        employee: MyProfileEmployee.fromJson(_map(j['employee']) ?? const {}),
        personal: PersonalDetails.fromJson(_map(j['personal']) ?? const {}),
        timeline: _maps(j['timeline']).map(TimelineEvent.fromJson).toList(growable: false),
      );
  @override
  List<Object?> get props => [employee, personal, timeline];
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 1C — requests, leave and approvals (policy/requests.js, approvals.js)
// ═══════════════════════════════════════════════════════════════════════════

class RequestEmployee extends Equatable {
  const RequestEmployee({required this.id, required this.fullName, this.employeeCode});
  final String id;
  final String fullName;
  final String? employeeCode;
  factory RequestEmployee.fromJson(Map<String, dynamic> j) => RequestEmployee(
        id: _str(j['id']) ?? '',
        fullName: _str(j['full_name']) ?? '',
        employeeCode: _str(j['employee_code']),
      );
  @override
  List<Object?> get props => [id, fullName, employeeCode];
}

class LateMark extends Equatable {
  const LateMark({this.lateMinutes, this.lateCount, required this.lateHalfDay, required this.lateExcused});
  final int? lateMinutes;
  final int? lateCount;
  final bool lateHalfDay;
  final bool lateExcused;
  factory LateMark.fromJson(Map<String, dynamic> j) => LateMark(
        lateMinutes: _int(j['late_minutes']),
        lateCount: _int(j['late_count']),
        lateHalfDay: _bool(j['late_half_day']),
        lateExcused: _bool(j['late_excused']),
      );
  @override
  List<Object?> get props => [lateMinutes, lateCount, lateHalfDay, lateExcused];
}

/// The context an approvals row carries (D1): how many of this kind this month, the day's late
/// mark, and who else is off that day.
class ApprovalContext extends Equatable {
  const ApprovalContext({this.typeThisMonth = 0, this.monthLimit, this.late, this.othersOffCount = 0, this.othersOffNames = const []});
  final int typeThisMonth;
  final int? monthLimit;
  final LateMark? late;
  final int othersOffCount;
  final List<String> othersOffNames;
  factory ApprovalContext.fromJson(Map<String, dynamic> j) {
    final off = _map(j['others_off']) ?? const {};
    return ApprovalContext(
      typeThisMonth: _int(j['type_this_month']) ?? 0,
      monthLimit: _int(j['month_limit']),
      late: _map(j['late']) == null ? null : LateMark.fromJson(_map(j['late'])!),
      othersOffCount: _int(off['count']) ?? 0,
      othersOffNames: _strings(off['names']),
    );
  }
  @override
  List<Object?> get props => [typeThisMonth, monthLimit, late, othersOffCount, othersOffNames];
}

/// One request (attendance or leave) as the app reads it (C1–C4, D1).
class EssRequest extends Equatable {
  const EssRequest({
    required this.id,
    required this.family,
    required this.type,
    required this.status,
    required this.day,
    required this.reason,
    this.createdAt,
    this.decidedAt,
    this.decidedByName,
    this.decisionNote,
    this.cancelledAt,
    this.cancelledByName,
    this.cancelReason,
    this.place,
    this.fixIn,
    this.fixOut,
    this.employee,
    this.context,
  });

  final String id;
  final String family; // attendance | leave
  final String type; // on_duty | fix_a_day | excuse_late | cl | lwp
  final String status; // pending | approved | rejected | withdrawn | cancelled
  final String day;
  final String reason;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String? decidedByName;
  final String? decisionNote;
  final DateTime? cancelledAt;
  final String? cancelledByName;
  final String? cancelReason;
  final String? place;
  final String? fixIn;
  final String? fixOut;
  final RequestEmployee? employee;
  final ApprovalContext? context;

  bool get isPending => status == 'pending';

  String get typeLabel => switch (type) {
        'on_duty' => 'On duty',
        'fix_a_day' => 'Fix a day',
        'excuse_late' => 'Excuse a late',
        'cl' => 'Casual leave',
        'lwp' => 'Leave without pay',
        _ => type,
      };

  factory EssRequest.fromJson(Map<String, dynamic> j) => EssRequest(
        id: _str(j['id']) ?? '',
        family: _str(j['family']) ?? 'attendance',
        type: _str(j['type']) ?? '',
        status: _str(j['status']) ?? 'pending',
        day: _str(j['day']) ?? '',
        reason: _str(j['reason']) ?? '',
        createdAt: _date(j['created_at']),
        decidedAt: _date(j['decided_at']),
        decidedByName: _str(j['decided_by_name']),
        decisionNote: _str(j['decision_note']),
        cancelledAt: _date(j['cancelled_at']),
        cancelledByName: _str(j['cancelled_by_name']),
        cancelReason: _str(j['cancel_reason']),
        place: _str(j['place']),
        fixIn: _str(j['fix_in']),
        fixOut: _str(j['fix_out']),
        employee: _map(j['employee']) == null ? null : RequestEmployee.fromJson(_map(j['employee'])!),
        context: _map(j['context']) == null ? null : ApprovalContext.fromJson(_map(j['context'])!),
      );

  @override
  List<Object?> get props => [id, family, type, status, day, reason, decidedByName, decisionNote];
}

/// `GET /approvals`.
class ApprovalInbox extends Equatable {
  const ApprovalInbox({this.attendance = 0, this.leave = 0, this.total = 0, required this.requests, required this.truncated});
  final int attendance;
  final int leave;
  final int total;
  final List<EssRequest> requests;
  final bool truncated;
  factory ApprovalInbox.fromJson(Map<String, dynamic> j) {
    final c = _map(j['counts']) ?? const {};
    return ApprovalInbox(
      attendance: _int(c['attendance']) ?? 0,
      leave: _int(c['leave']) ?? 0,
      total: _int(c['total']) ?? 0,
      requests: _maps(j['requests']).map(EssRequest.fromJson).toList(growable: false),
      truncated: _bool(j['truncated']),
    );
  }
  @override
  List<Object?> get props => [attendance, leave, total, requests];
}

/// One row of `GET /leave/balances`.
class LeaveBalanceType extends Equatable {
  const LeaveBalanceType({
    required this.type,
    required this.offered,
    required this.unit,
    required this.phase,
    this.allowed,
    required this.used,
    required this.pending,
    this.remaining,
  });
  final String type;
  final bool offered;
  final String unit; // days | minutes
  final int phase;
  final int? allowed;
  final int used;
  final int pending;
  final int? remaining;

  String get label => switch (type) {
        'on_duty' => 'On duty',
        'fix_a_day' => 'Fix a day',
        'excuse_late' => 'Excuse a late',
        'leave_cl' => 'Casual leave',
        'leave_lwp' => 'Leave without pay',
        'short_leave' => 'Short leave',
        'wfh' => 'Work from home',
        _ => type,
      };

  factory LeaveBalanceType.fromJson(Map<String, dynamic> j) => LeaveBalanceType(
        type: _str(j['type']) ?? '',
        offered: _bool(j['offered']),
        unit: _str(j['unit']) ?? 'days',
        phase: _int(j['phase']) ?? 1,
        allowed: _int(j['allowed']),
        used: _int(j['used']) ?? 0,
        pending: _int(j['pending']) ?? 0,
        remaining: _int(j['remaining']),
      );
  @override
  List<Object?> get props => [type, offered, allowed, used, pending, remaining];
}

class LeaveBalances extends Equatable {
  const LeaveBalances({required this.month, required this.types});
  final String month;
  final List<LeaveBalanceType> types;
  factory LeaveBalances.fromJson(Map<String, dynamic> j) =>
      LeaveBalances(month: _str(j['month']) ?? '', types: _maps(j['types']).map(LeaveBalanceType.fromJson).toList(growable: false));
  @override
  List<Object?> get props => [month, types];
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 1D — notifications (routes/notifications.js, policy/notifications.js)
// ═══════════════════════════════════════════════════════════════════════════

class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    this.data = const {},
    this.readAt,
    this.createdAt,
  });
  final String id;
  final String category;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get unread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: _str(j['id']) ?? '',
        category: _str(j['category']) ?? '',
        title: _str(j['title']) ?? '',
        body: _str(j['body']) ?? '',
        data: _map(j['data']) ?? const {},
        readAt: _date(j['read_at']),
        createdAt: _date(j['created_at']),
      );

  @override
  List<Object?> get props => [id, category, title, body, readAt, createdAt];
}

class NotificationPage extends Equatable {
  const NotificationPage({required this.notifications, required this.unread, required this.truncated});
  final List<AppNotification> notifications;
  final int unread;
  final bool truncated;
  factory NotificationPage.fromJson(Map<String, dynamic> j) => NotificationPage(
        notifications: _maps(j['notifications']).map(AppNotification.fromJson).toList(growable: false),
        unread: _int(j['unread']) ?? 0,
        truncated: _bool(j['truncated']),
      );
  @override
  List<Object?> get props => [notifications, unread, truncated];
}

class NotificationCategorySetting extends Equatable {
  const NotificationCategorySetting({required this.category, required this.enabled});
  final String category;
  final bool enabled;
  String get label => switch (category) {
        'approvals' => 'Approvals waiting for me',
        'decisions' => 'My requests decided',
        'priority_tasks' => 'Priority tasks',
        'mentions' => 'Mentions',
        'replies' => 'Replies',
        'praise' => 'Praise',
        'announcements' => 'Announcements',
        'acknowledgements' => 'Acknowledgements',
        'polls' => 'Polls',
        'helpdesk' => 'Helpdesk',
        _ => category,
      };
  factory NotificationCategorySetting.fromJson(Map<String, dynamic> j) =>
      NotificationCategorySetting(category: _str(j['category']) ?? '', enabled: _bool(j['enabled']));
  @override
  List<Object?> get props => [category, enabled];
}

class NotificationSettings extends Equatable {
  const NotificationSettings({required this.categories, this.quietFrom, this.quietTo});
  final List<NotificationCategorySetting> categories;
  final String? quietFrom;
  final String? quietTo;

  Set<String> get disabled => categories.where((c) => !c.enabled).map((c) => c.category).toSet();

  factory NotificationSettings.fromJson(Map<String, dynamic> j) {
    final quiet = _map(j['quiet_hours']) ?? const {};
    return NotificationSettings(
      categories: _maps(j['categories']).map(NotificationCategorySetting.fromJson).toList(growable: false),
      quietFrom: _str(quiet['from']),
      quietTo: _str(quiet['to']),
    );
  }
  @override
  List<Object?> get props => [categories, quietFrom, quietTo];
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 2A — the Wall (routes/wall*.js, routes/wallViews.js, policy/wall.js)
// ═══════════════════════════════════════════════════════════════════════════

class WallAttachment extends Equatable {
  const WallAttachment({this.name, this.contentType, this.url});
  final String? name;
  final String? contentType;
  final String? url;
  factory WallAttachment.fromJson(Map<String, dynamic> j) =>
      WallAttachment(name: _str(j['name']), contentType: _str(j['content_type']), url: _str(j['url']));
  @override
  List<Object?> get props => [name, contentType, url];
}

class WallPerson extends Equatable {
  const WallPerson({required this.id, required this.fullName, this.employeeCode, this.designation});
  final String id;
  final String fullName;
  final String? employeeCode;
  final String? designation;
  factory WallPerson.fromJson(Map<String, dynamic> j) => WallPerson(
        id: _str(j['id']) ?? '',
        fullName: _str(j['full_name']) ?? '',
        employeeCode: _str(j['employee_code']),
        designation: _str(j['designation']),
      );
  @override
  List<Object?> get props => [id, fullName, employeeCode, designation];
}

class WallReactionCounts extends Equatable {
  const WallReactionCounts({required this.counts, required this.total});
  final Map<String, int> counts;
  final int total;
  factory WallReactionCounts.fromJson(Map<String, dynamic> j) => WallReactionCounts(
        counts: j.map((k, v) => MapEntry(k, _int(v) ?? 0)),
        total: (j.values.fold<int>(0, (n, v) => n + (_int(v) ?? 0))),
      );
  @override
  List<Object?> get props => [counts, total];
}

class WallPollOption extends Equatable {
  const WallPollOption({required this.id, required this.label, this.position = 0, this.votes = 0});
  final String id;
  final String label;
  final int position;
  final int votes;
  factory WallPollOption.fromJson(Map<String, dynamic> j) => WallPollOption(
        id: _str(j['id']) ?? '',
        label: _str(j['label']) ?? '',
        position: _int(j['position']) ?? 0,
        votes: _int(j['votes']) ?? 0,
      );
  @override
  List<Object?> get props => [id, label, votes];
}

class WallPoll extends Equatable {
  const WallPoll({
    required this.multiple,
    required this.anonymous,
    this.closesOn,
    required this.closed,
    this.closedAt,
    required this.optionsLocked,
    required this.totalVotes,
    required this.myOptionIds,
    required this.options,
  });
  final bool multiple;
  final bool anonymous;
  final String? closesOn;
  final bool closed;
  final DateTime? closedAt;
  final bool optionsLocked;
  final int totalVotes;
  final List<String> myOptionIds;
  final List<WallPollOption> options;

  factory WallPoll.fromJson(Map<String, dynamic> j) => WallPoll(
        multiple: _bool(j['multiple']),
        anonymous: _bool(j['anonymous']),
        closesOn: _str(j['closes_on']),
        closed: _bool(j['closed']),
        closedAt: _date(j['closed_at']),
        optionsLocked: _bool(j['options_locked']),
        totalVotes: _int(j['total_votes']) ?? 0,
        myOptionIds: _strings(j['my_option_ids']),
        options: _maps(j['options']).map(WallPollOption.fromJson).toList(growable: false),
      );
  @override
  List<Object?> get props => [multiple, closed, totalVotes, myOptionIds, options];
}

/// One feed row (post | praise | wish | poll). A deleted row keeps only its place.
class WallPost extends Equatable {
  const WallPost({
    required this.id,
    required this.kind,
    this.scope = 'org',
    this.branchId,
    this.author,
    required this.mine,
    this.body,
    this.attachments = const [],
    this.mentions = const [],
    this.about,
    required this.edited,
    this.editedAt,
    this.createdAt,
    this.updatedAt,
    required this.hidden,
    required this.deleted,
    this.badgeId,
    this.badgeLabel,
    this.occasion,
    this.reactions,
    this.commentCount = 0,
    this.poll,
    this.myReaction,
  });

  final String id;
  final String kind;
  final String scope;
  final String? branchId;
  final WallPerson? author;
  final bool mine;
  final String? body;
  final List<WallAttachment> attachments;
  final List<WallPerson> mentions;
  final WallPerson? about;
  final bool edited;
  final DateTime? editedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool hidden;
  final bool deleted;
  final String? badgeId;
  final String? badgeLabel;
  final String? occasion;
  final WallReactionCounts? reactions;
  final int commentCount;
  final WallPoll? poll;
  final String? myReaction;

  bool get isPraise => kind == 'praise';

  factory WallPost.fromJson(Map<String, dynamic> j) {
    final badge = _map(j['badge']);
    return WallPost(
      id: _str(j['id']) ?? '',
      kind: _str(j['kind']) ?? 'post',
      scope: _str(j['scope']) ?? 'org',
      branchId: _str(j['branch_id']),
      author: _map(j['author']) == null ? null : WallPerson.fromJson(_map(j['author'])!),
      mine: _bool(j['mine']),
      body: _str(j['body']),
      attachments: _maps(j['attachments']).map(WallAttachment.fromJson).toList(growable: false),
      mentions: _maps(j['mentions']).map(WallPerson.fromJson).toList(growable: false),
      about: _map(j['about']) == null ? null : WallPerson.fromJson(_map(j['about'])!),
      edited: _bool(j['edited']),
      editedAt: _date(j['edited_at']),
      createdAt: _date(j['created_at']),
      updatedAt: _date(j['updated_at']),
      hidden: _bool(j['hidden']),
      deleted: _bool(j['deleted']),
      badgeId: badge == null ? null : _str(badge['id']),
      badgeLabel: badge == null ? null : _str(badge['label']),
      occasion: _str(j['occasion']),
      reactions: _map(j['reactions']) == null ? null : WallReactionCounts.fromJson(_map(j['reactions'])!),
      commentCount: _int(j['comment_count']) ?? 0,
      poll: _map(j['poll']) == null ? null : WallPoll.fromJson(_map(j['poll'])!),
      myReaction: _str(j['my_reaction']),
    );
  }

  @override
  List<Object?> get props => [id, kind, mine, body, edited, hidden, deleted, badgeId, reactions, commentCount, poll, myReaction];
}

class PraiseBadge extends Equatable {
  const PraiseBadge({required this.id, required this.label, this.forGroup});
  final String id;
  final String label;
  final String? forGroup;
  factory PraiseBadge.fromJson(Map<String, dynamic> j) =>
      PraiseBadge(id: _str(j['id']) ?? '', label: _str(j['label']) ?? '', forGroup: _str(j['for']));
  @override
  List<Object?> get props => [id, label, forGroup];
}

class PraisePage extends Equatable {
  const PraisePage({required this.praise, required this.badges});
  final List<WallPost> praise;
  final List<PraiseBadge> badges;
  factory PraisePage.fromJson(Map<String, dynamic> j) => PraisePage(
        praise: _maps(j['praise']).map(WallPost.fromJson).toList(growable: false),
        badges: _maps(j['badges']).map(PraiseBadge.fromJson).toList(growable: false),
      );
  @override
  List<Object?> get props => [praise, badges];
}

class WallComment extends Equatable {
  const WallComment({
    required this.id,
    this.postId,
    this.parentId,
    this.author,
    required this.mine,
    this.body,
    this.mentions = const [],
    this.reactions,
    this.replyCount = 0,
    this.createdAt,
    required this.edited,
    required this.hidden,
    required this.deleted,
    this.replies = const [],
    this.myReaction,
  });

  final String id;
  final String? postId;
  final String? parentId;
  final WallPerson? author;
  final bool mine;
  final String? body;
  final List<WallPerson> mentions;
  final WallReactionCounts? reactions;
  final int replyCount;
  final DateTime? createdAt;
  final bool edited;
  final bool hidden;
  final bool deleted;
  final List<WallComment> replies;
  final String? myReaction;

  factory WallComment.fromJson(Map<String, dynamic> j) => WallComment(
        id: _str(j['id']) ?? '',
        postId: _str(j['post_id']),
        parentId: _str(j['parent_id']),
        author: _map(j['author']) == null ? null : WallPerson.fromJson(_map(j['author'])!),
        mine: _bool(j['mine']),
        body: _str(j['body']),
        mentions: _maps(j['mentions']).map(WallPerson.fromJson).toList(growable: false),
        reactions: _map(j['reactions']) == null ? null : WallReactionCounts.fromJson(_map(j['reactions'])!),
        replyCount: _int(j['reply_count']) ?? 0,
        createdAt: _date(j['created_at']),
        edited: _bool(j['edited']),
        hidden: _bool(j['hidden']),
        deleted: _bool(j['deleted']),
        replies: _maps(j['replies']).map(WallComment.fromJson).toList(growable: false),
        myReaction: _str(j['my_reaction']),
      );

  @override
  List<Object?> get props => [id, postId, parentId, mine, body, edited, hidden, deleted, replyCount, replies, myReaction];
}

class WallFeed extends Equatable {
  const WallFeed({required this.posts, required this.truncated});
  final List<WallPost> posts;
  final bool truncated;
  factory WallFeed.fromJson(Map<String, dynamic> j) =>
      WallFeed(posts: _maps(j['posts']).map(WallPost.fromJson).toList(growable: false), truncated: _bool(j['truncated']));
  @override
  List<Object?> get props => [posts, truncated];
}

class WallSettings extends Equatable {
  const WallSettings({required this.kinds, required this.scopes, required this.reactions, required this.badges, required this.maxPhotos});
  final List<String> kinds;
  final List<String> scopes;
  final List<String> reactions;
  final List<PraiseBadge> badges;
  final int maxPhotos;
  factory WallSettings.fromJson(Map<String, dynamic> j) => WallSettings(
        kinds: _strings(j['kinds']),
        scopes: _strings(j['scopes']),
        reactions: _strings(j['reactions']),
        badges: _maps(j['badges']).map(PraiseBadge.fromJson).toList(growable: false),
        maxPhotos: _int(j['max_photos']) ?? 5,
      );
  @override
  List<Object?> get props => [kinds, scopes, reactions, badges, maxPhotos];
}

class WallAnnouncement extends Equatable {
  const WallAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    this.attachments = const [],
    this.author,
    required this.mine,
    this.audienceLabel,
    required this.needsAck,
    this.closesOn,
    required this.pinned,
    this.publishedAt,
    this.createdAt,
    this.readAt,
    this.ackAt,
  });
  final String id;
  final String title;
  final String body;
  final List<WallAttachment> attachments;
  final WallPerson? author;
  final bool mine;
  final String? audienceLabel;
  final bool needsAck;
  final String? closesOn;
  final bool pinned;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? readAt;
  final DateTime? ackAt;

  bool get acked => ackAt != null;
  bool get read => readAt != null;

  factory WallAnnouncement.fromJson(Map<String, dynamic> j) => WallAnnouncement(
        id: _str(j['id']) ?? '',
        title: _str(j['title']) ?? '',
        body: _str(j['body']) ?? '',
        attachments: _maps(j['attachments']).map(WallAttachment.fromJson).toList(growable: false),
        author: _map(j['author']) == null ? null : WallPerson.fromJson(_map(j['author'])!),
        mine: _bool(j['mine']),
        audienceLabel: _str(j['audience_label']),
        needsAck: _bool(j['needs_ack']),
        closesOn: _str(j['closes_on']),
        pinned: _bool(j['pinned']),
        publishedAt: _date(j['published_at']),
        createdAt: _date(j['created_at']),
        readAt: _date(j['read_at']),
        ackAt: _date(j['ack_at']),
      );
  @override
  List<Object?> get props => [id, title, mine, needsAck, pinned, readAt, ackAt];
}

class WallCelebration extends Equatable {
  const WallCelebration({required this.id, required this.kind, required this.person, this.on, this.daysAgo, this.wished = false});
  final String id;
  final String kind; // birthday | anniversary | new_joiner
  final WallPerson person;
  final String? on;
  final int? daysAgo;
  final bool wished;
  factory WallCelebration.fromJson(Map<String, dynamic> j) => WallCelebration(
        id: _str(j['id']) ?? '',
        kind: _str(j['kind']) ?? '',
        person: WallPerson.fromJson(_map(j['person']) ?? _map(j['employee']) ?? const {}),
        on: _str(j['on']),
        daysAgo: _int(j['days_ago']),
        wished: _bool(j['wished']),
      );
  @override
  List<Object?> get props => [id, kind, person, on, daysAgo, wished];
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 2B — Helpdesk (routes/helpdesk*.js, lib/helpdeskKit.js, policy/helpdesk.js)
// ═══════════════════════════════════════════════════════════════════════════

class HelpdeskCategory extends Equatable {
  const HelpdeskCategory({
    required this.id,
    required this.name,
    this.slug,
    required this.isTicket,
    this.flow,
    required this.confidential,
    required this.allowsHold,
    this.priority,
    this.firstResponseHours,
    this.resolutionHours,
  });
  final String id;
  final String name;
  final String? slug;
  final bool isTicket;
  final String? flow;
  final bool confidential;
  final bool allowsHold;
  final String? priority;
  final int? firstResponseHours;
  final int? resolutionHours;
  factory HelpdeskCategory.fromJson(Map<String, dynamic> j) => HelpdeskCategory(
        id: _str(j['id']) ?? '',
        name: _str(j['name']) ?? '',
        slug: _str(j['slug']),
        isTicket: _bool(j['is_ticket']),
        flow: _str(j['flow']),
        confidential: _bool(j['confidential']),
        allowsHold: _bool(j['allows_hold']),
        priority: _str(j['priority']),
        firstResponseHours: _int(j['first_response_hours']),
        resolutionHours: _int(j['resolution_hours']),
      );
  @override
  List<Object?> get props => [id, name, isTicket, flow, confidential, allowsHold, priority];
}

class HelpdeskSettings extends Equatable {
  const HelpdeskSettings({required this.categories, required this.reopenDays});
  final List<HelpdeskCategory> categories;
  final int reopenDays;
  factory HelpdeskSettings.fromJson(Map<String, dynamic> j) =>
      HelpdeskSettings(categories: _maps(j['categories']).map(HelpdeskCategory.fromJson).toList(growable: false), reopenDays: _int(j['reopen_days']) ?? 7);
  @override
  List<Object?> get props => [categories, reopenDays];
}

class HelpdeskTicket extends Equatable {
  const HelpdeskTicket({
    required this.id,
    required this.ref,
    required this.category,
    this.priority,
    required this.subject,
    this.body,
    required this.status,
    required this.anonymous,
    this.raisedBy,
    this.assignee,
    this.attachments = const [],
    this.firstResponseAt,
    this.firstResponseDueAt,
    this.resolutionDueAt,
    this.resolvedAt,
    this.closedAt,
    this.closingReason,
    this.rating,
    this.escalationLevel = 0,
    this.overdueMinutes,
    this.createdAt,
    this.updatedAt,
    required this.mine,
  });

  final String id;
  final String ref;
  final HelpdeskCategory category;
  final String? priority;
  final String subject;
  final String? body;
  final String status;
  final bool anonymous;
  final WallPerson? raisedBy;
  final WallPerson? assignee;
  final List<WallAttachment> attachments;
  final DateTime? firstResponseAt;
  final DateTime? firstResponseDueAt;
  final DateTime? resolutionDueAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final String? closingReason;
  final int? rating;
  final int escalationLevel;
  final int? overdueMinutes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool mine;

  bool get overdue => overdueMinutes != null;
  bool get isOpen => !['closed', 'withdrawn'].contains(status);

  factory HelpdeskTicket.fromJson(Map<String, dynamic> j) => HelpdeskTicket(
        id: _str(j['id']) ?? '',
        ref: _str(j['ref']) ?? '',
        category: HelpdeskCategory.fromJson(_map(j['category']) ?? const {}),
        priority: _str(j['priority']),
        subject: _str(j['subject']) ?? '',
        body: _str(j['body']),
        status: _str(j['status']) ?? 'open',
        anonymous: _bool(j['anonymous']),
        raisedBy: _map(j['raised_by']) == null ? null : WallPerson.fromJson(_map(j['raised_by'])!),
        assignee: _map(j['assignee']) == null ? null : WallPerson.fromJson(_map(j['assignee'])!),
        attachments: _maps(j['attachments']).map(WallAttachment.fromJson).toList(growable: false),
        firstResponseAt: _date(j['first_response_at']),
        firstResponseDueAt: _date(j['first_response_due_at']),
        resolutionDueAt: _date(j['resolution_due_at']),
        resolvedAt: _date(j['resolved_at']),
        closedAt: _date(j['closed_at']),
        closingReason: _str(j['closing_reason']),
        rating: _int(j['rating']),
        escalationLevel: _int(j['escalation_level']) ?? 0,
        overdueMinutes: _int(j['overdue_minutes']),
        createdAt: _date(j['created_at']),
        updatedAt: _date(j['updated_at']),
        mine: _bool(j['mine']),
      );

  @override
  List<Object?> get props => [id, ref, status, subject, priority, assignee, overdueMinutes, escalationLevel];
}

class HelpdeskMessage extends Equatable {
  const HelpdeskMessage({required this.id, this.ticketId, required this.kind, this.body, this.event, this.details = const {}, this.author, this.createdAt});
  final String id;
  final String? ticketId;
  final String kind; // comment | event
  final String? body;
  final String? event;
  final Map<String, dynamic> details;
  final WallPerson? author;
  final DateTime? createdAt;
  factory HelpdeskMessage.fromJson(Map<String, dynamic> j) => HelpdeskMessage(
        id: _str(j['id']) ?? '',
        ticketId: _str(j['ticket_id']),
        kind: _str(j['kind']) ?? 'comment',
        body: _str(j['body']),
        event: _str(j['event']),
        details: _map(j['details']) ?? const {},
        author: _map(j['author']) == null ? null : WallPerson.fromJson(_map(j['author'])!),
        createdAt: _date(j['created_at']),
      );
  @override
  List<Object?> get props => [id, kind, body, event, author, createdAt];
}

class HelpdeskTicketDetail extends Equatable {
  const HelpdeskTicketDetail({required this.ticket, required this.messages});
  final HelpdeskTicket ticket;
  final List<HelpdeskMessage> messages;
  factory HelpdeskTicketDetail.fromJson(Map<String, dynamic> j) => HelpdeskTicketDetail(
        ticket: HelpdeskTicket.fromJson(_map(j['ticket']) ?? const {}),
        messages: _maps(j['messages']).map(HelpdeskMessage.fromJson).toList(growable: false),
      );
  @override
  List<Object?> get props => [ticket, messages];
}

class HelpdeskQueue extends Equatable {
  const HelpdeskQueue({required this.tickets, required this.categories});
  final List<HelpdeskTicket> tickets;
  final List<HelpdeskCategory> categories;
  factory HelpdeskQueue.fromJson(Map<String, dynamic> j) => HelpdeskQueue(
        tickets: _maps(j['tickets']).map(HelpdeskTicket.fromJson).toList(growable: false),
        categories: _maps(j['categories']).map(HelpdeskCategory.fromJson).toList(growable: false),
      );
  @override
  List<Object?> get props => [tickets, categories];
}

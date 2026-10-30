import 'package:equatable/equatable.dart';

/// Models for the Scheduler's own punch path (`/api/hr/my-attendance`), which
/// the app calls directly (ADR-0006). The ESS `/attendance/day` read is separate
/// (see `ess_models.dart`).

Map<String, dynamic>? _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : null;
String? _str(dynamic v) => v?.toString();
int? _int(dynamic v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
double? _dbl(dynamic v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
bool _bool(dynamic v) => v == true;
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

List<Map<String, dynamic>> _maps(dynamic raw) => raw is List
    ? raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(growable: false)
    : const [];

class PunchChallenge extends Equatable {
  const PunchChallenge({required this.nonce, this.expiresAt});
  final String nonce;
  final DateTime? expiresAt;
  factory PunchChallenge.fromJson(Map<String, dynamic> j) =>
      PunchChallenge(nonce: _str(j['nonce']) ?? '', expiresAt: _date(j['expires_at']));
  @override
  List<Object?> get props => [nonce, expiresAt];
}

class AttendancePunch extends Equatable {
  const AttendancePunch({required this.kind, this.at, this.distanceM});
  final String kind; // in | out
  final DateTime? at;
  final int? distanceM;
  factory AttendancePunch.fromJson(Map<String, dynamic> j) =>
      AttendancePunch(kind: _str(j['kind']) ?? '', at: _date(j['at']), distanceM: _int(j['distance_m']));
  @override
  List<Object?> get props => [kind, at, distanceM];
}

class PunchToday extends Equatable {
  const PunchToday({
    required this.day,
    required this.punchedIn,
    required this.done,
    this.firstIn,
    this.lastOut,
    this.punches = const [],
    this.workedMinutes,
    this.cooldownSeconds,
    this.nextPunchAt,
    this.status,
    this.holiday,
    this.lateMinutes,
    this.earlyExitMinutes,
    this.lateHalfDay = false,
    this.lateExcused = false,
  });

  final String day;
  final bool punchedIn;
  final bool done;
  final DateTime? firstIn;
  final DateTime? lastOut;
  final List<AttendancePunch> punches;
  final int? workedMinutes;

  /// Seconds still to wait before the next punch, from the server clock. `done`
  /// is no longer "the day is over": a day may hold several in/out sessions.
  final int? cooldownSeconds;
  final DateTime? nextPunchAt;
  final String? status;
  final String? holiday;
  final int? lateMinutes;
  final int? earlyExitMinutes;
  final bool lateHalfDay;
  final bool lateExcused;

  factory PunchToday.fromJson(Map<String, dynamic> j) => PunchToday(
        day: _str(j['day']) ?? '',
        punchedIn: _bool(j['punched_in']),
        done: _bool(j['done']),
        firstIn: _date(j['first_in']),
        lastOut: _date(j['last_out']),
        punches: _maps(j['punches']).map(AttendancePunch.fromJson).toList(growable: false),
        workedMinutes: _int(j['worked_minutes']),
        cooldownSeconds: _int(j['cooldown_seconds']),
        nextPunchAt: _date(j['next_punch_at']),
        status: _str(j['status']),
        holiday: _str(j['holiday']),
        lateMinutes: _int(j['late_minutes']),
        earlyExitMinutes: _int(j['early_exit_minutes']),
        lateHalfDay: _bool(j['late_half_day']),
        lateExcused: _bool(j['late_excused']),
      );

  @override
  List<Object?> get props => [day, punchedIn, done, firstIn, lastOut, workedMinutes, cooldownSeconds, nextPunchAt, status];
}

class AttendanceDevice extends Equatable {
  const AttendanceDevice({required this.thisPhone, required this.hasRegisteredPhone, this.registeredAt});
  final String thisPhone; // own | unknown | other | revoked
  final bool hasRegisteredPhone;
  final DateTime? registeredAt;

  /// A phone with no registration may register on its first accepted punch.
  bool get canRegister => !hasRegisteredPhone && thisPhone == 'unknown';

  factory AttendanceDevice.fromJson(Map<String, dynamic> j) => AttendanceDevice(
        thisPhone: _str(j['this_phone']) ?? 'unknown',
        hasRegisteredPhone: _bool(j['has_registered_phone']),
        registeredAt: _date(j['registered_at']),
      );
  @override
  List<Object?> get props => [thisPhone, hasRegisteredPhone, registeredAt];
}

class AttendanceRules extends Equatable {
  const AttendanceRules({this.maxAccuracyM, this.mobileOnly = true});
  final double? maxAccuracyM;
  final bool mobileOnly;
  factory AttendanceRules.fromJson(Map<String, dynamic> j) =>
      AttendanceRules(maxAccuracyM: _dbl(j['max_accuracy_m']), mobileOnly: _bool(j['mobile_only']));
  @override
  List<Object?> get props => [maxAccuracyM, mobileOnly];
}
class AttendanceBranch extends Equatable {
  const AttendanceBranch({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
    this.radiusM,
    this.configured = false,
  });
  final String id;
  final String name;
  final double? latitude;
  final double? longitude;
  final double? radiusM;
  final bool configured;
  factory AttendanceBranch.fromJson(Map<String, dynamic> j) => AttendanceBranch(
        id: _str(j['id']) ?? '',
        name: _str(j['name']) ?? '',
        latitude: _dbl(j['latitude']),
        longitude: _dbl(j['longitude']),
        radiusM: _dbl(j['radius_m']),
        configured: _bool(j['configured']),
      );
  @override
  List<Object?> get props => [id, name, latitude, longitude, radiusM, configured];
}

class AttendanceShift extends Equatable {
  const AttendanceShift({this.name, this.start, this.end, this.graceMinutes});
  final String? name;
  final String? start;
  final String? end;
  final int? graceMinutes;
  factory AttendanceShift.fromJson(Map<String, dynamic> j) => AttendanceShift(
        name: _str(j['name']),
        start: _str(j['start']),
        end: _str(j['end']),
        graceMinutes: _int(j['grace_minutes']),
      );
  @override
  List<Object?> get props => [name, start, end, graceMinutes];
}

class AttendanceHoliday extends Equatable {
  const AttendanceHoliday({required this.day, required this.name});
  final String day;
  final String name;
  factory AttendanceHoliday.fromJson(Map<String, dynamic> j) =>
      AttendanceHoliday(day: _str(j['day']) ?? '', name: _str(j['name']) ?? '');
  @override
  List<Object?> get props => [day, name];
}

class AttendanceRemark extends Equatable {
  const AttendanceRemark({required this.day, required this.remarks, this.updatedAt});
  final String day;
  final String remarks;
  final DateTime? updatedAt;
  factory AttendanceRemark.fromJson(Map<String, dynamic> j) => AttendanceRemark(
        day: _str(j['day']) ?? '',
        remarks: _str(j['remarks']) ?? '',
        updatedAt: _date(j['updated_at']),
      );
  @override
  List<Object?> get props => [day, remarks, updatedAt];
}

class AttendanceMonthDay extends Equatable {
  const AttendanceMonthDay({
    required this.day,
    required this.status,
    this.leaveType,
    this.source,
    this.firstIn,
    this.lastOut,
    this.workedMinutes,
    this.lateMinutes,
    this.earlyExitMinutes,
    this.lateHalfDay = false,
    this.lateExcused = false,
  });
  final String day;
  final String status;
  final String? leaveType;
  final String? source;
  final DateTime? firstIn;
  final DateTime? lastOut;
  final int? workedMinutes;
  final int? lateMinutes;
  final int? earlyExitMinutes;
  final bool lateHalfDay;
  final bool lateExcused;

  factory AttendanceMonthDay.fromJson(Map<String, dynamic> j) => AttendanceMonthDay(
        day: _str(j['day']) ?? '',
        status: _str(j['status']) ?? 'unknown',
        leaveType: _str(j['leave_type']),
        source: _str(j['source']),
        firstIn: _date(j['first_in']),
        lastOut: _date(j['last_out']),
        workedMinutes: _int(j['worked_minutes']),
        lateMinutes: _int(j['late_minutes']),
        earlyExitMinutes: _int(j['early_exit_minutes']),
        lateHalfDay: _bool(j['late_half_day']),
        lateExcused: _bool(j['late_excused']),
      );

  @override
  List<Object?> get props => [day, status, firstIn, lastOut, workedMinutes];
}

/// `GET /hr/my-attendance`. Three shapes told apart by [linked]/[mustSetPassword].
class MyAttendance extends Equatable {
  const MyAttendance({
    required this.linked,
    this.message,
    this.mustSetPassword = false,
    this.employeeName,
    this.employeeCode,
    this.geofenceExempt = false,
    this.branch,
    this.shift,
    this.weekOffDays = const [],
    this.holidays = const [],
    this.upcomingHolidays = const [],
    this.myRemarks = const [],
    this.today,
    this.device,
    this.rules,
    this.month,
    this.days = const [],
  });

  final bool linked;
  final String? message;
  final bool mustSetPassword;
  final String? employeeName;
  final String? employeeCode;
  final bool geofenceExempt;
  final AttendanceBranch? branch;
  final AttendanceShift? shift;
  final List<int> weekOffDays;
  final List<AttendanceHoliday> holidays;
  final List<AttendanceHoliday> upcomingHolidays;
  final List<AttendanceRemark> myRemarks;
  final PunchToday? today;
  final AttendanceDevice? device;
  final AttendanceRules? rules;
  final String? month;
  final List<AttendanceMonthDay> days;

  factory MyAttendance.fromJson(Map<String, dynamic> j) {
    final employee = _map(j['employee']);
    return MyAttendance(
      linked: _bool(j['linked']),
      message: _str(j['message']),
      mustSetPassword: _bool(j['must_set_password']),
      employeeName: employee == null ? null : _str(employee['full_name']),
      employeeCode: employee == null ? null : _str(employee['employee_code']),
      geofenceExempt: employee != null && _bool(employee['geofence_exempt']),
      branch: _map(j['branch']) == null ? null : AttendanceBranch.fromJson(_map(j['branch'])!),
      shift: _map(j['shift']) == null ? null : AttendanceShift.fromJson(_map(j['shift'])!),
      weekOffDays: j['week_off_days'] is List
          ? (j['week_off_days'] as List).whereType<num>().map((e) => e.toInt()).toList(growable: false)
          : const [],
      holidays: _maps(j['holidays']).map(AttendanceHoliday.fromJson).toList(growable: false),
      upcomingHolidays: _maps(j['upcoming_holidays']).map(AttendanceHoliday.fromJson).toList(growable: false),
      myRemarks: _maps(j['my_remarks']).map(AttendanceRemark.fromJson).toList(growable: false),
      today: _map(j['today']) == null ? null : PunchToday.fromJson(_map(j['today'])!),
      device: _map(j['device']) == null ? null : AttendanceDevice.fromJson(_map(j['device'])!),
      rules: _map(j['rules']) == null ? null : AttendanceRules.fromJson(_map(j['rules'])!),
      month: _str(j['month']),
      days: _maps(j['days']).map(AttendanceMonthDay.fromJson).toList(growable: false),
    );
  }

  @override
  List<Object?> get props => [linked, mustSetPassword, today, device, branch, shift, month, days.length];
}

/// `PunchAccepted` (201).
class PunchAccepted extends Equatable {
  const PunchAccepted({
    required this.kind,
    this.at,
    this.distanceM,
    this.insideGeofence = false,
    this.flags = const [],
    this.deviceRegistered = false,
  });
  final String kind;
  final DateTime? at;
  final int? distanceM;
  final bool insideGeofence;
  final List<String> flags;
  final bool deviceRegistered;

  factory PunchAccepted.fromJson(Map<String, dynamic> j) => PunchAccepted(
        kind: _str(j['kind']) ?? '',
        at: _date(j['at']),
        distanceM: _int(j['distance_m']),
        insideGeofence: _bool(j['inside_geofence']),
        flags: j['flags'] is List ? (j['flags'] as List).map((e) => e.toString()).toList(growable: false) : const [],
        deviceRegistered: _bool(j['device_registered']),
      );

  @override
  List<Object?> get props => [kind, at, distanceM, insideGeofence, deviceRegistered];
}

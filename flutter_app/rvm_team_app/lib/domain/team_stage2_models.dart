// ignore_for_file: unnecessary_null_comparison, unnecessary_non_null_assertion
import 'package:equatable/equatable.dart';

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
double? _double(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');
String _str(Object? v) => v?.toString() ?? '';
DateTime? _date(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
bool _bool(Object? v) => v == true;
Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const {};
List<Map<String, dynamic>> _maps(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
    ];

// ── security (#52) ────────────────────────────────────────────────────────

class TeamAccess extends Equatable {
  const TeamAccess({
    required this.employeeName,
    required this.punchedIn,
    required this.onShift,
    required this.shiftStart,
    required this.shiftEnd,
    required this.deviceStatus,
    required this.devicePending,
    required this.sessionLive,
    required this.sessionSuperseded,
    required this.idleMinutes,
    required this.modules,
    required this.now,
  });

  final String employeeName;
  final bool punchedIn;
  final bool onShift;
  final String? shiftStart;
  final String? shiftEnd;
  final String deviceStatus;
  final bool devicePending;
  final bool sessionLive;
  final bool sessionSuperseded;
  final int idleMinutes;
  final Set<String> modules;
  final DateTime? now;

  bool get deviceBound => deviceStatus == 'bound';
  bool get mustPunchIn => !punchedIn;

  static TeamAccess fromJson(Map<String, dynamic> j) {
    final employee = _map(j['employee']);
    final shift = _map(j['shift']);
    final device = _map(j['device']);
    final session = _map(j['session']);
    return TeamAccess(
      employeeName: _str(employee['full_name']),
      punchedIn: _bool(j['punched_in']),
      onShift: _bool(j['on_shift']),
      shiftStart: shift['start']?.toString(),
      shiftEnd: shift['end']?.toString(),
      deviceStatus: _str(device['status']),
      devicePending: _bool(device['pending']),
      sessionLive: session.containsKey('live') ? _bool(session['live']) : true,
      sessionSuperseded: _bool(session['superseded']),
      idleMinutes: _int(j['idle_minutes']) ?? 30,
      modules: {
        for (final m in _maps(j['modules'])) _str(m['key']),
      },
      now: _date(j['now']),
    );
  }

  @override
  List<Object?> get props => [
        employeeName,
        punchedIn,
        onShift,
        deviceStatus,
        devicePending,
        sessionLive,
        sessionSuperseded,
        idleMinutes,
        modules,
      ];
}

class TeamSecurityAlert extends Equatable {
  const TeamSecurityAlert({
    required this.id,
    required this.kind,
    required this.day,
    required this.createdAt,
    required this.employeeName,
    required this.employeeCode,
    required this.module,
    required this.source,
    required this.records,
    required this.threshold,
  });

  final String id;
  final String kind;
  final String day;
  final DateTime? createdAt;
  final String? employeeName;
  final String? employeeCode;
  final String? module;
  final String? source;
  final int? records;
  final int? threshold;

  String get title => switch (kind) {
        'new_phone' => 'New phone waiting',
        'outside_shift' => 'Use outside shift',
        'many_records' => 'Many records opened',
        _ => kind.replaceAll('_', ' '),
      };

  static TeamSecurityAlert? tryParse(Object? v) {
    final j = v is Map ? v.cast<String, dynamic>() : null;
    if (j == null) return null;
    final id = _str(j['id']);
    if (id.isEmpty) return null;
    final employee = _map(j['employee']);
    final detail = _map(j['detail']);
    return TeamSecurityAlert(
      id: id,
      kind: _str(j['kind']),
      day: _str(j['day']),
      createdAt: _date(j['created_at']),
      employeeName: employee['full_name']?.toString(),
      employeeCode: employee['employee_code']?.toString(),
      module: detail['module']?.toString(),
      source: detail['source']?.toString(),
      records: _int(detail['records']),
      threshold: _int(detail['threshold']),
    );
  }

  @override
  List<Object?> get props => [id, kind, day, employeeName];
}

/// The idle lock's clock, kept out of the widget so the boundary is testable:
/// at [limit] the screen locks, one minute before it does not.
class IdleLock {
  const IdleLock({required this.limit, required this.lastActive});
  final Duration limit;
  final DateTime lastActive;

  bool lockedAt(DateTime now) => now.difference(lastActive) >= limit;
  Duration remainingAt(DateTime now) {
    final left = limit - now.difference(lastActive);
    return left.isNegative ? Duration.zero : left;
  }
}

// ── pending counts, branch health, fees (#53) ─────────────────────────────

class PendingCount extends Equatable {
  const PendingCount({
    required this.key,
    required this.count,
    required this.available,
    required this.list,
  });

  final String key;
  final int count;
  final bool available;
  final String list;

  String get label => switch (key) {
        'fee_followups_due' => 'Fee follow-ups due',
        'absent_three_in_a_row' => 'Absent three classes in a row',
        'fee_plan_pending' => 'Waiting for a fee plan',
        'paid_number_not_linked' => 'Paid number not linked',
        'complaints_open' => 'Open complaints',
        'phone_change_requests' => 'Phone changes',
        'extra_view_requests' => 'Extra views',
        'complaints_past_48_hours' => 'Complaints past 48 hours',
        'placement_flagged' => 'Placement proofs flagged',
        _ => key.replaceAll('_', ' '),
      };

  static PendingCount fromJson(Object? value) {
    final j = _map(value);
    return PendingCount(
      key: _str(j['key']),
      count: _int(j['count']) ?? 0,
      available: j['available'] != false,
      list: _str(j['list']),
    );
  }

  @override
  List<Object?> get props => [key, count, available, list];
}

class AbsentStreak extends Equatable {
  const AbsentStreak({
    required this.studentId,
    required this.studentName,
    required this.admissionNumber,
    required this.batchName,
    required this.lastAbsent,
    required this.lastPresent,
  });

  final String studentId;
  final String studentName;
  final String admissionNumber;
  final String? batchName;
  final String? lastAbsent;
  final String? lastPresent;

  static AbsentStreak? tryParse(Object? value) {
    final j = _map(value);
    if (j == null) return null;
    final id = _str(j['student_id']);
    if (id.isEmpty) return null;
    return AbsentStreak(
      studentId: id,
      studentName: _str(j['student_name']),
      admissionNumber: _str(j['admission_number']),
      batchName: j['batch_name']?.toString(),
      lastAbsent: j['last_absent']?.toString(),
      lastPresent: j['last_present']?.toString(),
    );
  }

  @override
  List<Object?> get props => [studentId, studentName, admissionNumber];
}

class JoiningCounts extends Equatable {
  const JoiningCounts(
      {this.expected = 0,
      this.pending = 0,
      this.allotted = 0,
      this.joined = 0});
  final int expected, pending, allotted, joined;
  static JoiningCounts fromJson(Object? value) {
    final j = _map(value);
    return JoiningCounts(
        expected: _int(j['expected']) ?? 0,
        pending: _int(j['pending']) ?? 0,
        allotted: _int(j['allotted']) ?? 0,
        joined: _int(j['joined']) ?? 0);
  }

  @override
  List<Object?> get props => [expected, pending, allotted, joined];
}

class BranchHealthRow extends Equatable {
  const BranchHealthRow({
    required this.locationId,
    required this.name,
    this.admissions,
    this.joining,
    this.attendanceMarked,
    this.attendancePresent,
    this.attendancePct,
    this.dropouts,
    this.overdue1to30,
    this.overdue31to60,
    this.overdueOver60,
    this.overdueTotal,
  });

  final int locationId;
  final String name;
  final int? admissions;
  final JoiningCounts? joining;
  final int? attendanceMarked;
  final int? attendancePresent;
  final double? attendancePct;
  final int? dropouts;
  final int? overdue1to30, overdue31to60, overdueOver60, overdueTotal;

  static BranchHealthRow? tryParse(Object? value) {
    final j = _map(value);
    if (j == null) return null;
    final id = _int(j['location_id']);
    if (id == null) return null;
    final attendance = _map(j['attendance']);
    final dropouts = _map(j['dropouts']);
    final overdue = _map(j['overdue_students']);
    return BranchHealthRow(
      locationId: id,
      name: _str(j['name']),
      admissions: j['admissions'] is Map ? null : _int(j['admissions']),
      joining: j['joining'] is Map ? JoiningCounts.fromJson(j['joining']) : null,
      attendanceMarked: _int(attendance['marked']),
      attendancePresent: _int(attendance['present']),
      attendancePct: _double(attendance['pct']),
      dropouts: _int(dropouts['count']),
      overdue1to30: _int(overdue['1_30']),
      overdue31to60: _int(overdue['31_60']),
      overdueOver60: _int(overdue['over_60']),
      overdueTotal: _int(overdue['total']),
    );
  }

  @override
  List<Object?> get props => [
        locationId,
        name,
        admissions,
        joining,
        attendanceMarked,
        attendancePresent,
        attendancePct,
        dropouts,
        overdue1to30,
        overdue31to60,
        overdueOver60,
        overdueTotal,
      ];
}

class BranchHealth extends Equatable {
  const BranchHealth(
      {required this.from, required this.to, required this.branches});
  final String from, to;
  final List<BranchHealthRow> branches;

  static BranchHealth fromJson(Map<String, dynamic> j) => BranchHealth(
        from: _str(j['from']),
        to: _str(j['to']),
        branches: [
          for (final r in _maps(j['branches']))
            if (BranchHealthRow.tryParse(r) case final row?) row,
        ],
      );

  @override
  List<Object?> get props => [from, to, branches];
}

class BranchMoneyRow extends Equatable {
  const BranchMoneyRow({
    required this.locationId,
    required this.name,
    required this.billedPaise,
    required this.collectedPaise,
    required this.outstandingPaise,
    required this.overduePaise,
  });

  final int locationId;
  final String name;
  final int billedPaise, collectedPaise, outstandingPaise, overduePaise;

  static BranchMoneyRow? tryParse(Object? value) {
    final j = _map(value);
    if (j == null) return null;
    final id = _int(j['location_id']);
    if (id == null) return null;
    final age = _map(j['overdue_paise_by_age']);
    return BranchMoneyRow(
      locationId: id,
      name: _str(j['name']),
      billedPaise: _int(j['billed_paise']) ?? 0,
      collectedPaise: _int(j['collected_paise']) ?? 0,
      outstandingPaise: _int(j['outstanding_paise']) ?? 0,
      overduePaise: _int(age['total']) ?? 0,
    );
  }

  @override
  List<Object?> get props =>
      [locationId, name, billedPaise, collectedPaise, outstandingPaise, overduePaise];
}

class BranchHealthMoney extends Equatable {
  const BranchHealthMoney(
      {required this.from,
      required this.to,
      required this.branches,
      required this.totalBilled,
      required this.totalCollected,
      required this.totalOutstanding,
      required this.totalOverdue});
  final String from, to;
  final List<BranchMoneyRow> branches;
  final int totalBilled, totalCollected, totalOutstanding, totalOverdue;

  static BranchHealthMoney fromJson(Map<String, dynamic> j) {
    final total = _map(j['total']);
    final age = _map(total['overdue_paise_by_age']);
    return BranchHealthMoney(
      from: _str(j['from']),
      to: _str(j['to']),
      branches: [
        for (final r in _maps(j['branches']))
          if (BranchMoneyRow.tryParse(r) case final row?) row,
      ],
      totalBilled: _int(total['billed_paise']) ?? 0,
      totalCollected: _int(total['collected_paise']) ?? 0,
      totalOutstanding: _int(total['outstanding_paise']) ?? 0,
      totalOverdue: _int(age['total']) ?? 0,
    );
  }

  @override
  List<Object?> get props =>
      [from, to, branches, totalBilled, totalCollected, totalOutstanding, totalOverdue];
}

/// A fee follow-up row. No money field exists on this model by design (D9).
class FeeFollowup extends Equatable {
  const FeeFollowup({
    required this.admissionId,
    required this.studentName,
    required this.admissionNumber,
    required this.phoneMasked,
    required this.courses,
    required this.batchName,
    required this.callDueDate,
    required this.daysOverdue,
    required this.lastRemark,
    required this.lastOutcome,
    required this.lastContactAt,
    required this.source,
    required this.callPriority,
  });

  final String admissionId;
  final String studentName;
  final String admissionNumber;
  final String? phoneMasked;
  final String? courses;
  final String? batchName;
  final String? callDueDate;
  final int daysOverdue;
  final String? lastRemark;
  final String? lastOutcome;
  final DateTime? lastContactAt;
  final String source;
  final String? callPriority;

  static FeeFollowup? tryParse(Object? value) {
    final j = _map(value);
    if (j == null) return null;
    final id = _str(j['admission_id']);
    if (id.isEmpty) return null;
    return FeeFollowup(
      admissionId: id,
      studentName: _str(j['student_name']),
      admissionNumber: _str(j['admission_number']),
      phoneMasked: j['phone_masked']?.toString(),
      courses: j['courses']?.toString(),
      batchName: j['batch_name']?.toString(),
      callDueDate: j['call_due_date']?.toString(),
      daysOverdue: _int(j['days_overdue']) ?? 0,
      lastRemark: j['last_remark']?.toString(),
      lastOutcome: j['last_outcome']?.toString(),
      lastContactAt: _date(j['last_contact_at']),
      source: _str(j['source']),
      callPriority: j['call_priority']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
        admissionId,
        studentName,
        admissionNumber,
        phoneMasked,
        courses,
        batchName,
        callDueDate,
        daysOverdue,
        lastRemark,
        lastOutcome,
        lastContactAt,
        source,
        callPriority,
      ];
}

class FeeList extends Equatable {
  const FeeList({
    required this.tab,
    required this.source,
    required this.date,
    required this.today,
    required this.overdue,
    required this.upcoming,
    required this.rows,
  });

  final String tab, source, date;
  final int today, overdue, upcoming;
  final List<FeeFollowup> rows;

  static FeeList fromJson(Map<String, dynamic> j) {
    final counts = _map(j['counts']);
    return FeeList(
      tab: _str(j['tab']),
      source: _str(j['source']),
      date: _str(j['date']),
      today: _int(counts['today']) ?? 0,
      overdue: _int(counts['overdue']) ?? 0,
      upcoming: _int(counts['upcoming']) ?? 0,
      rows: [
        for (final r in _maps(j['rows']))
          if (FeeFollowup.tryParse(r) case final row?) row,
      ],
    );
  }

  @override
  List<Object?> get props =>
      [tab, source, date, today, overdue, upcoming, rows];
}

class FeeHistoryRow extends Equatable {
  const FeeHistoryRow({
    required this.id,
    required this.at,
    required this.type,
    required this.outcome,
    required this.remark,
    required this.nextFollowupDate,
    required this.by,
  });

  final int id;
  final DateTime? at;
  final String type;
  final String? outcome;
  final String? remark;
  final String? nextFollowupDate;
  final String by;

  static FeeHistoryRow? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _int(j['id']);
    if (id == null) return null;
    return FeeHistoryRow(
      id: id,
      at: _date(j['at']),
      type: _str(j['type']),
      outcome: j['outcome']?.toString(),
      remark: j['remark']?.toString(),
      nextFollowupDate: j['next_follow_up_date']?.toString(),
      by: _str(j['by']),
    );
  }

  @override
  List<Object?> get props => [id, at, type, outcome, remark, nextFollowupDate, by];
}

class FeeShare extends Equatable {
  const FeeShare(
      {required this.userId,
      required this.name,
      required this.locationId,
      required this.since});
  final String userId, name;
  final int? locationId;
  final DateTime? since;

  static FeeShare? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['user_id']);
    if (id == null || id.isEmpty) return null;
    return FeeShare(
        userId: id,
        name: _str(j['name']),
        locationId: _int(j['location_id']),
        since: _date(j['since']));
  }

  @override
  List<Object?> get props => [userId, name, locationId, since];
}

class FeeShares extends Equatable {
  const FeeShares({required this.mine, required this.withMe});
  final List<FeeShare> mine, withMe;

  static FeeShares fromJson(Map<String, dynamic> j) => FeeShares(
        mine: [
          for (final r in _maps(j['mine']))
            if (FeeShare.tryParse(r) case final row?) row,
        ],
        withMe: [
          for (final r in _maps(j['with_me']))
            if (FeeShare.tryParse(r) case final row?) row,
        ],
      );

  @override
  List<Object?> get props => [mine, withMe];
}

class FeeOutcomeDraft extends Equatable {
  const FeeOutcomeDraft({
    this.status = 'Answered',
    this.remark = '',
    this.nextDate,
  });

  final String status;
  final String remark;
  final DateTime? nextDate;

  FeeOutcomeDraft copyWith(
          {String? status, String? remark, DateTime? nextDate, bool clearDate = false}) =>
      FeeOutcomeDraft(
        status: status ?? this.status,
        remark: remark ?? this.remark,
        nextDate: clearDate ? null : (nextDate ?? this.nextDate),
      );

  /// The Scheduler refuses today: the next follow-up is tomorrow or later.
  String? validate({DateTime? now}) {
    if (status != 'Answered' && status != 'No Answer') {
      return 'Choose Answered or No Answer.';
    }
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final next = nextDate;
    if (next == null) return 'Pick the next follow-up date.';
    final picked = DateTime(next.year, next.month, next.day);
    if (!picked.isAfter(day)) return 'The next follow-up must be tomorrow or later.';
    return null;
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        if (remark.trim().isNotEmpty) 'notes': remark.trim(),
        'next_follow_up_date': _dayString(nextDate!),
      };

  static String _dayString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  List<Object?> get props => [status, remark, nextDate];
}

// ── scorecards (#55) ──────────────────────────────────────────────────────

class ScoreNumber extends Equatable {
  const ScoreNumber({
    required this.key,
    required this.value,
    required this.unit,
    required this.target,
    required this.better,
    required this.state,
    required this.available,
    required this.detail,
  });

  final String key;
  final num? value;
  final String unit;
  final num? target;
  final String better;
  final String state;
  final bool available;
  final Map<String, dynamic> detail;

  String get label => switch (key) {
        'overdue_cleared' => 'Overdue cleared',
        'joining_allotted' => 'Joining allotted',
        'joining_joined' => 'Joined',
        'attendance_pct' => 'Attendance',
        'dropouts' => 'Dropouts',
        'complaints_within_48h' => 'Complaints within 48h',
        'followups_on_time_pct' => 'Follow-ups on time',
        'joining_vs_target' => 'Joining vs target',
        'collections_paise' => 'Collections',
        'overdue_paise_by_age' => 'Overdue by age',
        'collections_pct' => 'Collections %',
        'joining_rate' => 'Joining rate',
        'dropout_rate' => 'Dropout rate',
        'overdue_over_60_paise' => 'Overdue over 60 days',
        _ => key.replaceAll('_', ' '),
      };

  bool get isMoney => unit == 'paise';

  static ScoreNumber? tryParse(Object? value) {
    final j = _map(value);
    final key = j == null ? null : _str(j['key']);
    if (key == null || key.isEmpty) return null;
    return ScoreNumber(
      key: key,
      value: j!['value'] is num ? j['value'] as num : num.tryParse('${j['value']}'),
      unit: _str(j['unit']),
      target: j['target'] is num ? j['target'] as num : num.tryParse('${j['target']}'),
      better: _str(j['better']),
      state: _str(j['state']),
      available: j['available'] != false,
      detail: _map(j['detail']),
    );
  }

  @override
  List<Object?> get props =>
      [key, value, unit, target, better, state, available, detail];
}

class ScoreBranch extends Equatable {
  const ScoreBranch(
      {required this.locationId, required this.name, required this.numbers});
  final int locationId;
  final String name;
  final List<ScoreNumber> numbers;

  static ScoreBranch? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _int(j['location_id']);
    if (id == null) return null;
    return ScoreBranch(
      locationId: id,
      name: _str(j['name']),
      numbers: [
        for (final n in _maps(j['numbers']))
          if (ScoreNumber.tryParse(n) case final number?) number,
      ],
    );
  }

  @override
  List<Object?> get props => [locationId, name, numbers];
}

class Scorecard extends Equatable {
  const Scorecard({
    required this.audience,
    required this.periodKind,
    required this.startsOn,
    required this.endsOn,
    required this.branches,
  });

  final String audience, periodKind, startsOn, endsOn;
  final List<ScoreBranch> branches;

  static Scorecard fromJson(Map<String, dynamic> j) {
    final period = _map(j['period']);
    return Scorecard(
      audience: _str(j['audience']),
      periodKind: _str(period['kind']),
      startsOn: _str(period['starts_on']),
      endsOn: _str(period['ends_on']),
      branches: [
        for (final b in _maps(j['branches']))
          if (ScoreBranch.tryParse(b) case final branch?) branch,
      ]..sort((a, b) => a.locationId.compareTo(b.locationId)),
    );
  }

  /// Hide a money number for the Admin Manager even if a reply ever carries it
  /// (D9). The server already omits it; this is the client's last guard.
  Scorecard withoutMoneyForAdminManager() => audience == 'admin_manager'
      ? Scorecard(
          audience: audience,
          periodKind: periodKind,
          startsOn: startsOn,
          endsOn: endsOn,
          branches: [
            for (final b in branches)
              ScoreBranch(
                  locationId: b.locationId,
                  name: b.name,
                  numbers: [
                    for (final n in b.numbers)
                      if (!n.isMoney) n,
                  ]),
          ],
        )
      : this;

  @override
  List<Object?> get props =>
      [audience, periodKind, startsOn, endsOn, branches];
}

class ScoreTarget extends Equatable {
  const ScoreTarget({
    required this.metricKey,
    required this.locationId,
    required this.period,
    required this.startsOn,
    required this.value,
    required this.better,
  });
  final String metricKey, period, startsOn, better;
  final int locationId;
  final num? value;

  static ScoreTarget? tryParse(Object? value) {
    final j = _map(value);
    final key = j == null ? null : _str(j['metric_key']);
    if (key == null || key.isEmpty) return null;
    return ScoreTarget(
      metricKey: key,
      locationId: _int(j!['location_id']) ?? 0,
      period: _str(j['period']),
      startsOn: _str(j['starts_on']),
      value: j['value'] is num ? j['value'] as num : null,
      better: _str(j['better']),
    );
  }

  @override
  List<Object?> get props =>
      [metricKey, locationId, period, startsOn, value, better];
}

class TargetsView extends Equatable {
  const TargetsView(
      {required this.period,
      required this.canSet,
      required this.keys,
      required this.targets});
  final String period, canSet;
  final List<Map<String, dynamic>> keys;
  final List<ScoreTarget> targets;

  static TargetsView fromJson(Map<String, dynamic> j) => TargetsView(
        period: _str(j['period']),
        canSet: _str(j['can_set']),
        keys: _maps(j['keys']),
        targets: [
          for (final t in _maps(j['targets']))
            if (ScoreTarget.tryParse(t) case final target?) target,
        ],
      );

  @override
  List<Object?> get props => [period, canSet, keys, targets];
}

// ── social (#54) ──────────────────────────────────────────────────────────

class SocialMe extends Equatable {
  const SocialMe(
      {required this.employeeId,
      required this.name,
      required this.role,
      required this.shoots});
  final String employeeId, name, role;
  final List<SocialShoot> shoots;

  static SocialMe fromJson(Map<String, dynamic> j) => SocialMe(
        employeeId: _str(j['employee_id']),
        name: _str(j['name']),
        role: _str(j['role']),
        shoots: [
          for (final s in _maps(j['shoots']))
            if (SocialShoot.tryParse(s) case final shoot?) shoot,
        ],
      );

  @override
  List<Object?> get props => [employeeId, name, role, shoots];
}

class SocialAccount extends Equatable {
  const SocialAccount({
    required this.id,
    required this.brand,
    required this.platform,
    required this.name,
    required this.handle,
    required this.active,
  });
  final String id, brand, platform, name, handle;
  final bool active;

  static SocialAccount? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null || id.isEmpty) return null;
    return SocialAccount(
        id: id,
        brand: _str(j['brand']),
        platform: _str(j['platform']),
        name: _str(j['name']),
        handle: _str(j['handle']),
        active: j['active'] != false);
  }

  @override
  List<Object?> get props => [id, brand, platform, name, handle, active];
}

class SocialPerson extends Equatable {
  const SocialPerson({required this.employeeId, required this.name});
  final String employeeId, name;

  static SocialPerson? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['employee_id']);
    if (id == null || id.isEmpty) return null;
    return SocialPerson(employeeId: id, name: _str(j['name']));
  }

  @override
  List<Object?> get props => [employeeId, name];
}

class SocialCard extends Equatable {
  const SocialCard({
    required this.id,
    required this.kind,
    required this.title,
    required this.stage,
    required this.editorName,
    required this.accounts,
    required this.brief,
    required this.deadline,
    required this.postDate,
    required this.postUrl,
    required this.todoAt,
    required this.doneAt,
    required this.liveAt,
    required this.createdAt,
    required this.editStage,
  });

  final String id, kind, title, stage;
  final String? editorName;
  final List<SocialAccount> accounts;
  final Map<String, dynamic> brief;
  final String? deadline, postDate, postUrl, editStage;
  final DateTime? todoAt, doneAt, liveAt, createdAt;

  bool get isEditorAction => stage == 'todo';
  bool get isLive => stage == 'live';

  static SocialCard? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null || id.isEmpty) return null;
    final editor = _map(j['editor']);
    return SocialCard(
      id: id,
      kind: _str(j['kind']),
      title: _str(j['title']),
      stage: _str(j['stage']),
      editorName: editor['name']?.toString(),
      accounts: [
        for (final a in _maps(j['accounts']))
          if (SocialAccount.tryParse(a) case final account?) account,
      ],
      brief: _map(j['brief']),
      deadline: j['deadline']?.toString(),
      postDate: j['post_date']?.toString(),
      postUrl: j['post_url']?.toString(),
      todoAt: _date(j['todo_at']),
      doneAt: _date(j['done_at']),
      liveAt: _date(j['live_at']),
      createdAt: _date(j['created_at']),
      editStage: j['edit_stage']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        kind,
        title,
        stage,
        editorName,
        accounts,
        brief,
        deadline,
        postDate,
        postUrl,
        todoAt,
        doneAt,
        liveAt,
        createdAt,
        editStage,
      ];
}

class SocialShoot extends Equatable {
  const SocialShoot({
    required this.id,
    required this.cardId,
    required this.title,
    required this.day,
    required this.startTime,
    required this.minutes,
    required this.place,
    required this.prepare,
    required this.status,
    required this.people,
    required this.cuts,
    required this.liveCuts,
  });

  final String id, cardId;
  final String? title;
  final String day, startTime;
  final int minutes;
  final String place, prepare, status;
  final List<SocialPerson> people;
  final int cuts, liveCuts;

  static SocialShoot? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null || id.isEmpty) return null;
    final progress = _map(j['progress']);
    return SocialShoot(
      id: id,
      cardId: _str(j['card_id']),
      title: j['title']?.toString(),
      day: _str(j['day']),
      startTime: _str(j['start_time']),
      minutes: _int(j['minutes']) ?? 60,
      place: _str(j['place']),
      prepare: _str(j['prepare']),
      status: _str(j['status']),
      people: [
        for (final p in _maps(j['people']))
          if (SocialPerson.tryParse(p) case final person?) person,
      ],
      cuts: _int(progress['cuts']) ?? 0,
      liveCuts: _int(progress['live']) ?? 0,
    );
  }

  String get progressLabel => '$liveCuts of $cuts cuts live';

  @override
  List<Object?> get props =>
      [id, cardId, title, day, startTime, minutes, place, prepare, status, people, cuts, liveCuts];
}

class SocialHome extends Equatable {
  const SocialHome({
    required this.role,
    required this.stuck,
    required this.kitty,
    required this.todayPosts,
    required this.todayShoots,
  });
  final String role;
  final List<SocialCard> stuck, kitty, todayPosts;
  final List<SocialShoot> todayShoots;

  static SocialHome fromJson(Map<String, dynamic> j) => SocialHome(
        role: _str(j['role']),
        stuck: [
          for (final c in _maps(j['stuck']))
            if (SocialCard.tryParse(c) case final card?) card,
        ],
        kitty: [
          for (final c in _maps(j['kitty']))
            if (SocialCard.tryParse(c) case final card?) card,
        ],
        todayPosts: [
          for (final c in _maps(j['today_posts']))
            if (SocialCard.tryParse(c) case final card?) card,
        ],
        todayShoots: [
          for (final s in _maps(j['today_shoots']))
            if (SocialShoot.tryParse(s) case final shoot?) shoot,
        ],
      );

  @override
  List<Object?> get props =>
      [role, stuck, kitty, todayPosts, todayShoots];
}

class FreeSlot extends Equatable {
  const FreeSlot(
      {required this.day, required this.startTime, required this.endTime});
  final String day, startTime, endTime;

  static FreeSlot? tryParse(Object? value) {
    final j = _map(value);
    final day = j == null ? null : _str(j['day']);
    if (day == null || day.isEmpty) return null;
    return FreeSlot(
        day: day,
        startTime: _str(j['start_time']),
        endTime: _str(j['end_time']));
  }

  @override
  List<Object?> get props => [day, startTime, endTime];
}

// ── desk and placement (#56) ───────────────────────────────────────────────

class DeskQueue extends Equatable {
  const DeskQueue(
      {required this.key, required this.count, required this.available});
  final String key;
  final int count;
  final bool available;

  String get label => switch (key) {
        'number_not_linked' || 'paid_number_not_linked' => 'Number not linked',
        'phone_change_requests' || 'phone_changes' => 'Phone change requests',
        'extra_view_requests' || 'view_requests' => 'Extra view requests',
        'fee_plan_pending' => 'Waiting for a fee plan',
        'absent_three_in_a_row' => 'Absent three in a row',
        'complaints_open' => 'Open complaints',
        _ => key.replaceAll('_', ' '),
      };

  static DeskQueue fromJson(Map<String, dynamic> j, {String? key}) =>
      DeskQueue(
        key: key ?? _str(j['key']),
        count: _int(j['count']) ?? 0,
        available: j['available'] != false,
      );

  @override
  List<Object?> get props => [key, count, available];
}

class LinkCandidate extends Equatable {
  const LinkCandidate({
    required this.studentId,
    required this.name,
    required this.admissionNumber,
    required this.course,
    required this.batch,
    required this.phoneMasked,
  });
  final String studentId, name, admissionNumber, course, batch;
  final String? phoneMasked;

  static LinkCandidate? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['student_id'] ?? j['id']);
    if (id == null || id.isEmpty) return null;
    return LinkCandidate(
      studentId: id,
      name: _str(j['student_name'] ?? j['name']),
      admissionNumber: _str(j['admission_number']),
      course: _str(j['course']),
      batch: _str(j['batch_name'] ?? j['batch']),
      phoneMasked: j['phone_masked']?.toString(),
    );
  }

  @override
  List<Object?> get props =>
      [studentId, name, admissionNumber, course, batch, phoneMasked];
}

class LinkRequest extends Equatable {
  const LinkRequest({
    required this.id,
    required this.studentName,
    required this.admissionNumber,
    required this.phoneMasked,
    required this.createdAt,
  });
  final String id, studentName, admissionNumber;
  final String? phoneMasked;
  final DateTime? createdAt;

  static LinkRequest? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null || id.isEmpty) return null;
    return LinkRequest(
      id: id,
      studentName: _str(j['student_name'] ?? j['name']),
      admissionNumber: _str(j['admission_number']),
      phoneMasked: j['phone_masked']?.toString(),
      createdAt: _date(j['created_at']),
    );
  }

  @override
  List<Object?> get props => [id, studentName, admissionNumber, phoneMasked, createdAt];
}

class PhoneChangeRequest extends Equatable {
  const PhoneChangeRequest({
    required this.id,
    required this.studentName,
    required this.oldMasked,
    required this.newMasked,
    required this.createdAt,
  });
  final String id, studentName;
  final String? oldMasked, newMasked;
  final DateTime? createdAt;

  static PhoneChangeRequest? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null || id.isEmpty) return null;
    return PhoneChangeRequest(
      id: id,
      studentName: _str(j['student_name'] ?? j['name']),
      oldMasked: j['old_phone_masked']?.toString(),
      newMasked: j['new_phone_masked']?.toString(),
      createdAt: _date(j['created_at']),
    );
  }

  @override
  List<Object?> get props => [id, studentName, oldMasked, newMasked, createdAt];
}

class ViewRequest extends Equatable {
  const ViewRequest({
    required this.id,
    required this.studentName,
    required this.videoTitle,
    required this.viewsUsed,
    required this.createdAt,
  });
  final String id, studentName, videoTitle;
  final int viewsUsed;
  final DateTime? createdAt;

  static ViewRequest? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null || id.isEmpty) return null;
    return ViewRequest(
      id: id,
      studentName: _str(j['student_name'] ?? j['name']),
      videoTitle: _str(j['video_title']),
      viewsUsed: _int(j['views_used']) ?? 0,
      createdAt: _date(j['created_at']),
    );
  }

  @override
  List<Object?> get props => [id, studentName, videoTitle, viewsUsed, createdAt];
}

class PlacementFollowup extends Equatable {
  const PlacementFollowup({
    required this.entryId,
    required this.companyName,
    required this.phoneMasked,
    required this.status,
    required this.nextFollowUpOn,
    required this.lastCallOutcome,
    required this.latestRemark,
  });
  final String entryId;
  final String? companyName, phoneMasked, status, nextFollowUpOn, lastCallOutcome, latestRemark;

  static PlacementFollowup? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['entry_id']);
    if (id == null || id.isEmpty) return null;
    return PlacementFollowup(
      entryId: id,
      companyName: j['company_name']?.toString(),
      phoneMasked: j['phone_masked']?.toString(),
      status: j['status']?.toString(),
      nextFollowUpOn: j['next_follow_up_on']?.toString(),
      lastCallOutcome: j['last_call_outcome']?.toString(),
      latestRemark: j['latest_remark']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
        entryId,
        companyName,
        phoneMasked,
        status,
        nextFollowUpOn,
        lastCallOutcome,
        latestRemark,
      ];
}

class PlacementVerification extends Equatable {
  const PlacementVerification({
    required this.id,
    required this.studentName,
    required this.company,
    required this.role,
    required this.source,
    required this.createdAt,
    required this.ageDays,
    required this.flagged,
    required this.status,
    required this.hasProof,
    required this.studentCall,
    required this.companyCall,
  });
  final String id, source, status;
  final String? studentName, company, role;
  final DateTime? createdAt, studentCall, companyCall;
  final int ageDays;
  final bool flagged, hasProof;

  static PlacementVerification? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null || id.isEmpty) return null;
    return PlacementVerification(
      id: id,
      studentName: j['student_name']?.toString(),
      company: j['company']?.toString(),
      role: j['role']?.toString(),
      source: _str(j['source']),
      createdAt: _date(j['created_at']),
      ageDays: _int(j['age_days']) ?? 0,
      flagged: j['flagged'] == true,
      status: _str(j['status']),
      hasProof: j['has_proof'] == true,
      studentCall: _date(j['student_call']),
      companyCall: _date(j['company_call']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        studentName,
        company,
        role,
        source,
        createdAt,
        ageDays,
        flagged,
        status,
        hasProof,
        studentCall,
        companyCall,
      ];
}

// ── complaints and moderation (#58) ───────────────────────────────────────

class ComplaintRow extends Equatable {
  const ComplaintRow({
    required this.id,
    required this.category,
    required this.studentName,
    required this.course,
    required this.batch,
    required this.status,
    required this.createdAt,
    required this.replyDue,
    required this.resolveDue,
    required this.overdueReply,
    required this.overdueResolve,
    required this.reopened,
    required this.queue,
  });

  final String id, category, studentName, course, batch, status, queue;
  final DateTime? createdAt, replyDue, resolveDue;
  final bool overdueReply, overdueResolve, reopened;

  static ComplaintRow? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null || id.isEmpty) return null;
    return ComplaintRow(
      id: id,
      category: _str(j['category']),
      studentName: _str(j['student_name']),
      course: _str(j['course']),
      batch: _str(j['batch_name'] ?? j['batch']),
      status: _str(j['status']),
      createdAt: _date(j['created_at']),
      replyDue: _date(j['reply_due_at']),
      resolveDue: _date(j['resolve_due_at']),
      overdueReply: j['reply_overdue'] == true,
      overdueResolve: j['resolve_overdue'] == true,
      reopened: j['reopened'] == true,
      queue: _str(j['queue']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        category,
        studentName,
        course,
        batch,
        status,
        createdAt,
        replyDue,
        resolveDue,
        overdueReply,
        overdueResolve,
        reopened,
        queue,
      ];
}

class ComplaintMessage extends Equatable {
  const ComplaintMessage(
      {required this.id,
      required this.author,
      required this.body,
      required this.createdAt});
  final String id, author, body;
  final DateTime? createdAt;

  static ComplaintMessage? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null) return null;
    return ComplaintMessage(
        id: id,
        author: _str(j['author']),
        body: _str(j['body']),
        createdAt: _date(j['created_at']));
  }

  @override
  List<Object?> get props => [id, author, body, createdAt];
}

class ComplaintThread extends Equatable {
  const ComplaintThread(
      {required this.complaint,
      required this.description,
      required this.messages});
  final ComplaintRow complaint;
  final String description;
  final List<ComplaintMessage> messages;

  static ComplaintThread? fromJson(Map<String, dynamic> j) {
    final complaint = ComplaintRow.tryParse(j['complaint'] ?? j);
    if (complaint == null) return null;
    return ComplaintThread(
      complaint: complaint,
      description: _str(j['description']),
      messages: [
        for (final m in _maps(j['messages']))
          if (ComplaintMessage.tryParse(m) case final message?) message,
      ],
    );
  }

  @override
  List<Object?> get props => [complaint, description, messages];
}

class ModerationReport extends Equatable {
  const ModerationReport({
    required this.id,
    required this.postId,
    required this.postText,
    required this.group,
    required this.reports,
    required this.hidden,
  });
  final String id, postId, postText, group;
  final int reports;
  final bool hidden;

  static ModerationReport? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null || id.isEmpty) return null;
    return ModerationReport(
      id: id,
      postId: _str(j['post_id']),
      postText: _str(j['post_text'] ?? j['text']),
      group: _str(j['group_name'] ?? j['group']),
      reports: _int(j['reports']) ?? 1,
      hidden: j['hidden'] == true,
    );
  }

  @override
  List<Object?> get props => [id, postId, postText, group, reports, hidden];
}

class ModerationAction extends Equatable {
  const ModerationAction(
      {required this.id,
      required this.action,
      required this.actor,
      required this.at});
  final String id, action, actor;
  final DateTime? at;

  static ModerationAction? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null) return null;
    return ModerationAction(
        id: id,
        action: _str(j['action']),
        actor: _str(j['actor']),
        at: _date(j['at']));
  }

  @override
  List<Object?> get props => [id, action, actor, at];
}

// ── faculty test marks (#57) ───────────────────────────────────────────────

class BatchTest extends Equatable {
  const BatchTest({
    required this.id,
    required this.courseId,
    required this.moduleName,
    required this.maxMarks,
    required this.testDate,
    required this.scores,
  });
  final String id, courseId, moduleName;
  final num maxMarks;
  final String testDate;
  final List<Map<String, dynamic>> scores;

  static BatchTest? tryParse(Object? value) {
    final j = _map(value);
    final id = j == null ? null : _str(j['id']);
    if (id == null || id.isEmpty) return null;
    return BatchTest(
      id: id,
      courseId: _str(j['course_id']),
      moduleName: _str(j['module_name']),
      maxMarks: j['max_marks'] is num ? j['max_marks'] as num : 100,
      testDate: _str(j['test_date']),
      scores: _maps(j['scores'] ?? j['marks']),
    );
  }

  @override
  List<Object?> get props =>
      [id, courseId, moduleName, maxMarks, testDate, scores];
}

class MarksRosterRow extends Equatable {
  const MarksRosterRow({
    required this.studentId,
    required this.name,
    required this.admissionNumber,
    this.marks,
    this.absent = false,
  });
  final String studentId, name, admissionNumber;
  final num? marks;
  final bool absent;

  MarksRosterRow copyWith({num? marks, bool? absent, bool clearMarks = false}) =>
      MarksRosterRow(
        studentId: studentId,
        name: name,
        admissionNumber: admissionNumber,
        marks: clearMarks ? null : (marks ?? this.marks),
        absent: absent ?? this.absent,
      );

  Map<String, dynamic> toJson() => absent
      ? {'student_id': studentId, 'absent': true}
      : {'student_id': studentId, 'marks': marks ?? 0};

  @override
  List<Object?> get props =>
      [studentId, name, admissionNumber, marks, absent];
}

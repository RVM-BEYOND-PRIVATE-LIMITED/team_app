/// Staff dashboard KPIs (GET /api/dashboard `metrics`). The backend scopes the
/// numbers to the caller's branch (or globally for super/accounts admins).
class DashboardMetrics {
  const DashboardMetrics({
    this.totalAdmissions = 0,
    this.admissionsThisMonth = 0,
    this.totalCollected = 0,
    this.totalOutstanding = 0,
    this.overdueCount = 0,
    this.pendingUndertakings = 0,
  });

  final int totalAdmissions;
  final int admissionsThisMonth;
  final num totalCollected;
  final num totalOutstanding;
  final int overdueCount;
  final int pendingUndertakings;
}

/// The dashboard as the staff home renders it: KPI metrics plus the previous
/// day's average attendance (a separate stub endpoint today).
class DashboardSummary {
  const DashboardSummary({required this.metrics, this.yesterdayAttendance = 0});

  final DashboardMetrics metrics;
  final int yesterdayAttendance;
}

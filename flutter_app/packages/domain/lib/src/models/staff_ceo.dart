/// CEO command-centre models (super-admin). The four endpoints are aggregated
/// into one [CeoData] for a single scrollable screen.

class CeoOverview {
  const CeoOverview({
    this.totalStudents = 0,
    this.studentsJoined = 0,
    this.activeBatches = 0,
    this.totalFaculty = 0,
    this.activeFaculty = 0,
    this.onLeaveFaculty = 0,
  });
  final int totalStudents;
  final int studentsJoined;
  final int activeBatches;
  final int totalFaculty;
  final int activeFaculty;
  final int onLeaveFaculty;
}

class CeoFinance {
  const CeoFinance({
    this.revenueInPeriod = 0,
    this.predictedRevenue = 0,
    this.totalOutstandingDebt = 0,
    this.paymentMethods = const {},
  });
  final num revenueInPeriod;
  final num predictedRevenue;
  final num totalOutstandingDebt;

  /// method name → collected amount.
  final Map<String, num> paymentMethods;
}

class CeoOperations {
  const CeoOperations({this.overdueFollowUps = 0, this.admissionStatus = const {}});
  final int overdueFollowUps;

  /// approval status → count.
  final Map<String, int> admissionStatus;
}

class CeoDashboard {
  const CeoDashboard({required this.overview, required this.finance, required this.operations});
  final CeoOverview overview;
  final CeoFinance finance;
  final CeoOperations operations;
}

/// One day on the CEO trend line (GET /ceo/trends → an array of these).
class CeoTrendPoint {
  const CeoTrendPoint({
    required this.date,
    this.admissions = 0,
    this.joined = 0,
    this.revenue = 0,
    this.ticketsOpened = 0,
    this.ticketsResolved = 0,
  });
  final String date;
  final int admissions;
  final int joined;
  final num revenue;
  final int ticketsOpened;
  final int ticketsResolved;
}

/// GET /ceo/collection-rate-intelligence — the scalar KPIs (the day/mode/center
/// breakdown arrays are available server-side but not surfaced in mobile).
class CeoCollectionIntel {
  const CeoCollectionIntel({
    this.collectionRate = 0,
    this.totalReceiptsAmount = 0,
    this.revenueGap = 0,
    this.expectedRevenueBenchmark = 0,
    this.avgAdmissions3Mo = 0,
    this.prevCollectionRate = 0,
    this.changeAmount = 0,
    this.changePct = 0,
  });
  final num collectionRate;
  final num totalReceiptsAmount;
  final num revenueGap;
  final num expectedRevenueBenchmark;
  final num avgAdmissions3Mo;
  final num prevCollectionRate;
  final num changeAmount;
  final num changePct;
}

/// GET /ceo/faculty-attendance — yesterday's faculty attendance snapshot.
class CeoFacultyAttendance {
  const CeoFacultyAttendance({
    this.date,
    this.totalFaculty = 0,
    this.presentCount = 0,
    this.absentCount = 0,
    this.attendancePct = 0,
    this.isLive = false,
  });
  final String? date;
  final int totalFaculty;
  final int presentCount;
  final int absentCount;
  final num attendancePct;
  final bool isLive;
}

/// The four CEO endpoints aggregated. The dashboard is critical; the rest degrade
/// to null/empty so one failing endpoint doesn't blank the whole screen.
class CeoData {
  const CeoData({this.dashboard, this.trends = const [], this.collection, this.attendance});
  final CeoDashboard? dashboard;
  final List<CeoTrendPoint> trends;
  final CeoCollectionIntel? collection;
  final CeoFacultyAttendance? attendance;
}

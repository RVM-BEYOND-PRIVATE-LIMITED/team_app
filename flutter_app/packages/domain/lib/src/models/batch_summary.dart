/// Scheduler batch, trimmed to what list/detail screens actually render.
enum BatchStatus { upcoming, active, completed, unknown }

class BatchSummary {
  const BatchSummary({
    required this.id,
    required this.name,
    required this.status,
    this.facultyName,
    this.skillName,
    this.startDate,
    this.endDate,
    this.startTime,
    this.endTime,
    this.joinedCount,
    this.maxStudents,
  });

  final String id;
  final String name;
  final BatchStatus status;
  final String? facultyName;
  final String? skillName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? startTime;
  final String? endTime;
  final int? joinedCount;
  final int? maxStudents;
}

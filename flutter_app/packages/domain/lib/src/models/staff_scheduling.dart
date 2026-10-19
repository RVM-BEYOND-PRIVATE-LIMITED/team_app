import 'staff_substitution.dart' show NamedRef;

/// Faculty scheduling helpers — the free-slot finder (GET /free-slots) and the
/// skill-based faculty suggester (POST /suggestions/suggest-faculty).

/// One faculty's free slots across the queried date range.
class FacultyFreeSlots {
  const FacultyFreeSlots({required this.faculty, this.days = const []});
  final NamedRef faculty;
  final List<FreeSlotDay> days;
}

/// The free time windows on one date, as pre-formatted "HH:MM - HH:MM" strings.
class FreeSlotDay {
  const FreeSlotDay({required this.date, this.times = const []});
  final String date;
  final List<String> times;
}

/// A suggested faculty for a batch, with the common free windows across the
/// requested days and an availability [status].
class FacultySuggestion {
  const FacultySuggestion({
    required this.id,
    required this.name,
    this.commonSlots = const [],
    this.status = 'available',
  });
  final String id;
  final String name;
  final List<TimeRange> commonSlots;

  /// 'available' | 'available_other_times'.
  final String status;

  bool get isFullyAvailable => status == 'available';
}

class TimeRange {
  const TimeRange({required this.start, required this.end});
  final String start;
  final String end;
}

/// POST /suggestions/suggest-faculty body. [daysOfWeek] are day names; the
/// optional [startTime]/[endTime] narrow to a specific window.
class SuggestFacultyQuery {
  const SuggestFacultyQuery({
    required this.skillId,
    required this.startDate,
    required this.endDate,
    required this.daysOfWeek,
    this.startTime,
    this.endTime,
  });

  final String skillId;
  final String startDate;
  final String endDate;
  final List<String> daysOfWeek;
  final String? startTime;
  final String? endTime;

  Map<String, dynamic> toJson() => {
        'skillId': skillId,
        'startDate': startDate,
        'endDate': endDate,
        'daysOfWeek': daysOfWeek,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
      };
}

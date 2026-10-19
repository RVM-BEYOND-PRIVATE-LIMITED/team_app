import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler faculty-scheduling helpers over the Bearer-JWT Dio — the free-slot
/// finder and the skill-based faculty suggester. Both are branch-scoped reads.
class SchedulingRemoteDataSource with DioExecutor {
  SchedulingRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /free-slots — faculty free windows over a date range (400 without both
  /// dates). Optionally narrow by [facultyId] / [skillId].
  Future<List<FacultyFreeSlots>> freeSlots({
    required String startDate,
    required String endDate,
    String? facultyId,
    String? skillId,
  }) =>
      guard(() async => Parse.freeSlots((await _dio.get('/free-slots', queryParameters: {
            'startDate': startDate,
            'endDate': endDate,
            if (facultyId != null) 'selectedFaculty': facultyId,
            if (skillId != null) 'selectedSkill': skillId,
          }))
              .data));

  /// POST /suggestions/suggest-faculty — faculty who can cover a batch by skill,
  /// dates + day-names, and (optionally) a time window.
  Future<List<FacultySuggestion>> suggestFaculty(SuggestFacultyQuery query) => guard(() async =>
      Parse.facultySuggestions((await _dio.post('/suggestions/suggest-faculty', data: query.toJson())).data));
}

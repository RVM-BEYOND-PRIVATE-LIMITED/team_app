import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler course catalog over the Bearer-JWT Dio. List/detail read the course
/// with its book count / book list; delete 409s when the course is still
/// attached to admissions. Create/update also manage linked books via an RPC —
/// exposed here for completeness, but the mobile forms are deferred (an omitted
/// book_ids wipes associations; a books picker is needed first).
class CoursesRemoteDataSource with DioExecutor {
  CoursesRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /courses — all courses with `book_count` + `price_formatted`.
  Future<List<Course>> list() =>
      guard(() async => Parse.courses((await _dio.get('/courses')).data));

  /// GET /courses/:id — a course with its full linked-book list.
  Future<Course> byId(String id) =>
      guard(() async => Parse.courseOf((await _dio.get('/courses/$id')).data));

  /// POST /courses — returns `{id, name, price}` (books managed via book_ids).
  Future<Course> create(CourseDraft draft) =>
      guard(() async => Parse.courseOf((await _dio.post('/courses', data: draft.toJson())).data));

  /// PUT /courses/:id — replaces name/price AND the linked-book set.
  Future<Course> update(String id, CourseDraft draft) =>
      guard(() async => Parse.courseOf((await _dio.put('/courses/$id', data: draft.toJson())).data));

  /// DELETE /courses/:id — 204; 409 when the course is assigned to admissions.
  Future<void> delete(String id) => guard(() async {
        await _dio.delete('/courses/$id');
      });
}

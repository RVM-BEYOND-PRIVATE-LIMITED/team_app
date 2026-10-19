import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';
import 'multipart.dart';

/// App feedback over the JobPortal Dio. POST /feedback allows anonymous submits;
/// the screenshot upload + "my feedback" list require an authenticated session.
class FeedbackRemoteDataSource with DioExecutor {
  FeedbackRemoteDataSource(this._dio);

  final Dio _dio;

  /// Returns the new feedback id.
  Future<String> submit(FeedbackDraft draft) => guard(() async {
        final res = await _dio.post('/feedback', data: draft.toJson());
        return asMap(res.data)['id']?.toString() ?? '';
      });

  /// Uploads a screenshot and returns its `storage_path`, to attach to a submit.
  Future<String> uploadScreenshot(List<int> bytes, String filename) => guard(() async {
        final form = FormData()..files.add(MapEntry('file', multipartFromBytes(bytes, filename)));
        final res = await _dio.post('/feedback/screenshot', data: form);
        return asMap(res.data)['storage_path']?.toString() ?? '';
      });

  Future<List<FeedbackItem>> myFeedback({int page = 1}) => guard(() async =>
      Parse.feedbackItems((await _dio.get('/feedback', queryParameters: {'page': page})).data));
}

/// A feedback submission ready to POST. Kept in the data layer so blocs/UI never
/// hand-build backend JSON.
class FeedbackDraft {
  const FeedbackDraft({
    required this.type,
    required this.title,
    required this.description,
    this.screenshotStoragePath,
  });

  final FeedbackType type;
  final String title;
  final String description;
  final String? screenshotStoragePath;

  Map<String, dynamic> toJson() => {
        'feedback_type': feedbackTypeWire(type),
        'title': title,
        'description': description,
        if (screenshotStoragePath != null && screenshotStoragePath!.isNotEmpty)
          'screenshot_storage_path': screenshotStoragePath,
      };
}

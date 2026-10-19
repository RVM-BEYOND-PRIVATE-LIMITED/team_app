import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Candidate ↔ admin support chat over the JobPortal Dio.
class ChatRemoteDataSource with DioExecutor {
  ChatRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET returns the conversation + messages. 404 PROFILE_INCOMPLETE surfaces
  /// as a NotFoundFailure (candidate must finish their profile first).
  Future<ChatThread> thread() =>
      guard(() async => Parse.chatThread((await _dio.get('/candidates/chat')).data));

  Future<ChatMessage> send(String content) => guard(() async => Parse.chatMessage(
      asMap((await _dio.post('/candidates/chat/messages', data: {'content': content})).data)));
}

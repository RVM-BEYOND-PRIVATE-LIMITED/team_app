import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Candidate support tickets over the JobPortal Dio.
class SupportRemoteDataSource with DioExecutor {
  SupportRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<SupportTicket>> tickets() =>
      guard(() async => Parse.supportTickets((await _dio.get('/candidates/support-tickets')).data));

  Future<SupportTicket> create({required String subject, required String message}) =>
      guard(() async => Parse.supportTicket(asMap(
          (await _dio.post('/candidates/support-tickets', data: {'subject': subject, 'message': message}))
              .data)));

  Future<TicketDetail> ticket(String id) => guard(
      () async => Parse.ticketDetail(asMap((await _dio.get('/candidates/support-tickets/$id')).data)));

  Future<TicketReply> reply(String id, String message) => guard(() async => Parse.ticketReply(
      asMap((await _dio.post('/candidates/support-tickets/$id/replies', data: {'message': message})).data)));
}

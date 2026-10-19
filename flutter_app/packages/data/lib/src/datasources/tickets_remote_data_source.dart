import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler support-ticket management over the Bearer-JWT Dio. Reads auto-scope
/// to the caller's branch (super-admin may pass [locationId] to focus a city);
/// the write ops (status/priority/assignee, reopen, delete, chat reply) are
/// gated server-side. Ticket CREATION is student-side (requires a student_id)
/// and is intentionally not exposed here.
class TicketsRemoteDataSource with DioExecutor {
  TicketsRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /tickets — paginated; filter by status/category/search + date range.
  Future<TicketsPage> list({
    String? status,
    String? category,
    String? search,
    String? locationId,
    String? from,
    String? to,
    int page = 1,
    int limit = 15,
  }) =>
      guard(() async => Parse.ticketsPage((await _dio.get('/tickets', queryParameters: {
            'page': page,
            'limit': limit,
            if (status != null && status != 'All') 'status': status,
            if (category != null && category != 'All') 'category': category,
            if (search != null && search.isNotEmpty) 'search': search,
            if (from != null) 'from': from,
            if (to != null) 'to': to,
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// GET /tickets/:id — the full ticket.
  Future<StaffTicket> detail(String id) =>
      guard(() async => Parse.ticketOf((await _dio.get('/tickets/$id')).data));

  /// POST /tickets — raise a ticket on behalf of a student (returns the row).
  Future<StaffTicket> create(TicketDraft draft) =>
      guard(() async => Parse.ticketOf((await _dio.post('/tickets', data: draft.toJson())).data));

  /// GET /tickets/:ticketId/chat — the message thread (ascending).
  Future<List<TicketMessage>> chat(String ticketId) =>
      guard(() async => Parse.ticketMessages((await _dio.get('/tickets/$ticketId/chat')).data));

  /// GET /tickets/admins — admins assignable for the branch (super-admin may
  /// scope by [locationId]).
  Future<List<NamedRef>> admins({String? locationId}) =>
      guard(() async => Parse.ticketAdmins((await _dio.get('/tickets/admins', queryParameters: {
            if (locationId != null) 'location_id': locationId,
          }))
              .data));

  /// GET /tickets/categories — the distinct category names, for the filter.
  Future<List<String>> categories() =>
      guard(() async => Parse.ticketCategories((await _dio.get('/tickets/categories')).data));

  /// PATCH /tickets/:id — change status / priority / assignee.
  Future<void> update(String id, TicketUpdate update) => guard(() async {
        await _dio.patch('/tickets/$id', data: update.toJson());
      });

  /// POST /tickets/:id/reopen — reopen a resolved ticket.
  Future<void> reopen(String id) => guard(() async {
        await _dio.post('/tickets/$id/reopen');
      });

  /// DELETE /tickets/:id — 204 No Content.
  Future<void> delete(String id) => guard(() async {
        await _dio.delete('/tickets/$id');
      });

  /// POST /tickets/:ticketId/chat — post a reply (server blocks a Resolved
  /// ticket with 403; an admin's first reply auto-assigns the ticket to them).
  Future<void> reply({required String ticketId, required String message}) => guard(() async {
        await _dio.post('/tickets/$ticketId/chat', data: {'message': message});
      });
}

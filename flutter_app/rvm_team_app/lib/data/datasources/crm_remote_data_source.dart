import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';

import '../../domain/crm_models.dart';
import '../../domain/quiz_models.dart';
import '../../router/module_routes.dart';
import '../dio_executor.dart';
import '../module_request.dart';

/// The Sales CRM API on the Scheduler (team_app #51, Scheduler_Backend #163,
/// #164, #170, #171, #168).
///
/// Every request carries [TeamModule.crm] so a 404 `NOT_FOUND` from a closed
/// switch reads as "module off" (`ModuleUnavailableFailure`), not "no data".
/// The mutating calls also carry an `Idempotency-Key`; a form passes its own
/// [idempotencyKey] so a retry is the same action, never a second one. A lead
/// number travels only in a request body; it never appears in a path, a query
/// or a log.
class CrmRemoteDataSource with DioExecutor {
  CrmRemoteDataSource(this._dio);

  final Dio _dio;

  static Options _options(
          {String? idempotencyKey, bool module = true, bool soft = false}) =>
      Options(
        extra: {
          if (module) ...?TeamModule.crm.requestOptions.extra,
          if (idempotencyKey != null && idempotencyKey.isNotEmpty)
            IdempotencyInterceptor.extraKey: idempotencyKey,
        },
        validateStatus: soft ? (status) => status != 401 : null,
      );

  Map<String, dynamic> _map(Object? body) {
    if (body is Map) return body.cast<String, dynamic>();
    throw const ParseFailure();
  }

  Future<CrmMe> me() => guard(() async {
        final res = await _dio.get<Object?>('/crm/me', options: _options());
        return CrmMe.fromJson(_map(bodyOf(res)));
      });

  Future<CrmSetup> setup() => guard(() async {
        final res = await _dio.get<Object?>('/crm/setup', options: _options());
        return CrmSetup.fromJson(_map(bodyOf(res)));
      });

  Future<CrmHome> home() => guard(() async {
        final res =
            await _dio.get<Object?>('/crm/dialer/home', options: _options());
        return CrmHome.fromJson(_map(bodyOf(res)));
      });

  Future<CrmNextLead> next({CrmBucket? bucket, String? idempotencyKey}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/crm/dialer/next',
          data: {if (bucket != null) 'bucket': bucket.wire},
          options: _options(idempotencyKey: idempotencyKey),
        );
        return CrmNextLead.fromJson(_map(bodyOf(res)));
      });

  Future<CrmHome> setBreak(
    bool onBreak, {
    String? reason,
    String? idempotencyKey,
  }) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/crm/dialer/break',
          data: {
            'on_break': onBreak,
            if (reason != null && reason.trim().isNotEmpty)
              'reason': reason.trim(),
          },
          options: _options(idempotencyKey: idempotencyKey),
        );
        final body = _map(bodyOf(res));
        // The break reply is not a home reply; keep the caller's counts by
        // asking again where they are needed.
        return CrmHome(
          followupsDueToday: 0,
          missed: 0,
          callbacksWaiting: 0,
          openCall: null,
          onBreak: body['on_break'] == true,
          autoDial: false,
        );
      });

  Future<CrmLeadPage> myLeads(
    CrmBucket bucket, {
    String? cursor,
    int limit = 50,
  }) =>
      guard(() async {
        final res = await _dio.get<Object?>(
          '/crm/my/leads',
          queryParameters: {
            'bucket': bucket.wire,
            'limit': limit,
            if (cursor != null) 'cursor': cursor,
          },
          options: _options(),
        );
        return CrmLeadPage.fromJson(_map(bodyOf(res)));
      });

  Future<CrmLeadDetail> lead(int leadId) => guard(() async {
        final res =
            await _dio.get<Object?>('/crm/leads/$leadId', options: _options());
        final detail = CrmLeadDetail.tryParse(bodyOf(res));
        if (detail == null) throw const ParseFailure();
        return detail;
      });

  Future<CrmTimelinePage> timeline(
    int leadId, {
    String? cursor,
    int limit = 50,
  }) =>
      guard(() async {
        final res = await _dio.get<Object?>(
          '/crm/leads/$leadId/timeline',
          queryParameters: {
            'limit': limit,
            if (cursor != null) 'cursor': cursor,
          },
          options: _options(),
        );
        return CrmTimelinePage.fromJson(_map(bodyOf(res)));
      });

  Future<CrmLookupResult> lookup(String phone, {String? idempotencyKey}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/crm/leads/lookup',
          data: {'phone': phone},
          options: _options(idempotencyKey: idempotencyKey),
        );
        return CrmLookupResult.fromJson(_map(bodyOf(res)));
      });

  Future<CrmAddLeadResult> addLead({
    required String name,
    required String phone,
    required String source,
    required int campaignId,
    String? altPhone,
    String? idempotencyKey,
  }) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/crm/leads',
          data: {
            'name': name,
            'phone': phone,
            'source': source,
            'campaign_id': campaignId,
            if (altPhone != null && altPhone.trim().isNotEmpty)
              'alt_phone': altPhone,
          },
          options: _options(idempotencyKey: idempotencyKey),
        );
        return CrmAddLeadResult.fromJson(_map(bodyOf(res)));
      });

  Future<CrmStartedCall> startCall(
    int leadId, {
    String origin = 'dialer',
    String? idempotencyKey,
  }) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/crm/leads/$leadId/call',
          data: {'client': 'app', 'origin': origin},
          options: _options(idempotencyKey: idempotencyKey),
        );
        return CrmStartedCall.fromJson(_map(bodyOf(res)));
      });

  /// The number a Call started on the web left for this phone (#51 item 14).
  Future<String> dial(int callId) => guard(() async {
        final res = await _dio.get<Object?>(
          '/crm/calls/$callId/dial',
          options: _options(),
        );
        final phone = _map(bodyOf(res))['phone'];
        if (phone is! String || phone.isEmpty) throw const ParseFailure();
        return phone;
      });

  Future<CrmDisposeResult> dispose(
    int callId,
    CrmDispositionDraft draft, {
    String? idempotencyKey,
  }) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/crm/calls/$callId/dispose',
          data: draft.toJson(),
          options: _options(idempotencyKey: idempotencyKey),
        );
        return CrmDisposeResult.fromJson(_map(bodyOf(res)));
      });

  Future<List<CrmFollowup>> followups({
    required DateTime from,
    required DateTime to,
  }) =>
      guard(() async {
        final res = await _dio.get<Object?>(
          '/crm/followups',
          queryParameters: {
            'from': _dateOnly(from),
            'to': _dateOnly(to),
          },
          options: _options(),
        );
        final body = _map(bodyOf(res));
        return [
          for (final item in (body['followups'] as List? ?? const []))
            if (CrmFollowup.tryParse(item) case final parsed?) parsed,
        ];
      });

  Future<CrmAddLeadResult> addReference(
    int leadId, {
    required String name,
    required String phone,
    String? idempotencyKey,
  }) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/crm/leads/$leadId/references',
          data: {'name': name, 'phone': phone},
          options: _options(idempotencyKey: idempotencyKey),
        );
        return CrmAddLeadResult.fromJson(_map(bodyOf(res)));
      });

  Future<void> transferToMe(int leadId, {String? idempotencyKey}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/crm/leads/$leadId/transfer-to-me',
          options: _options(idempotencyKey: idempotencyKey),
        );
        bodyOf(res);
      });

  Future<List<CrmWaTemplate>> waTemplates() => guard(() async {
        final res = await _dio.get<Object?>(
          '/crm/wa/templates',
          queryParameters: {'purpose': 'lead_screen'},
          options: _options(),
        );
        final body = _map(bodyOf(res));
        return [
          for (final item in (body['templates'] as List? ?? const []))
            if (CrmWaTemplate.tryParse(item) case final parsed?) parsed,
        ];
      });

  Future<void> sendWhatsapp(
    int leadId, {
    required int templateId,
    String? idempotencyKey,
  }) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/crm/leads/$leadId/whatsapp',
          data: {'template_id': templateId},
          options: _options(idempotencyKey: idempotencyKey),
        );
        bodyOf(res);
      });

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
  // ── sales quiz (#152, Scheduler_Backend #692) ───────────────────────────
  Future<QuizCurrent> quizCurrent() => guard(() async {
        final res =
            await _dio.get<Object?>('/crm/quiz/current', options: _options());
        return QuizCurrent.fromJson(_map(bodyOf(res)));
      });

  /// The quiz without throwing when the switch is closed or nothing is due.
  Future<({QuizCurrent? data, Failure? failure})> quizCurrentSafe() async {
    try {
      final res = await _dio.get<Object?>(
        '/crm/quiz/current',
        options: _options(soft: true),
      );
      final status = res.statusCode ?? 0;
      if (status == 404) return (data: null, failure: null);
      if (status < 200 || status >= 300) {
        return (data: null, failure: failureFromResponse(status, res.data));
      }
      return (data: QuizCurrent.fromJson(_map(res.data)), failure: null);
    } on DioException catch (e) {
      return (data: null, failure: Failure.fromDio(e));
    } on Failure catch (failure) {
      return (data: null, failure: failure);
    } catch (_) {
      return (data: null, failure: const UnknownFailure());
    }
  }

  Future<QuizOpened> quizOpen(int roundId, {String? idempotencyKey}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/crm/quiz/rounds/$roundId/open',
          options: _options(idempotencyKey: idempotencyKey),
        );
        return QuizOpened.fromJson(_map(bodyOf(res)));
      });

  Future<QuizAnswerResult> quizAnswer(int roundId, int choice,
          {String? idempotencyKey}) =>
      guard(() async {
        final res = await _dio.post<Object?>(
          '/crm/quiz/rounds/$roundId/answer',
          data: {'choice': choice},
          options: _options(idempotencyKey: idempotencyKey),
        );
        return QuizAnswerResult.fromJson(_map(bodyOf(res)));
      });

  Future<QuizMe> quizMe() => guard(() async {
        final res =
            await _dio.get<Object?>('/crm/quiz/me', options: _options());
        return QuizMe.fromJson(_map(bodyOf(res)));
      });

  Future<QuizResults> quizResults({
    required String from,
    required String to,
    String? userId,
  }) =>
      guard(() async {
        final res = await _dio.get<Object?>(
          '/crm/quiz/results',
          queryParameters: {
            'from': from,
            'to': to,
            if (userId != null) 'user_id': userId,
          },
          options: _options(),
        );
        return QuizResults.fromJson(_map(bodyOf(res)));
      });
}

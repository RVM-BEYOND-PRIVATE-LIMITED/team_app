import 'package:core_network/core_network.dart';

import '../../domain/crm_models.dart';
import '../../domain/quiz_models.dart';
import '../connectivity_guard.dart';
import '../datasources/crm_remote_data_source.dart';

/// The Sales CRM for the Team app (team_app #51). Every call checks that the
/// phone is online first, then returns the typed failure the data source
/// raised; a screen shows it, or maps it to the shared blocked state.
class CrmRepository with ConnectivityGuard {
  CrmRepository(
      {required CrmRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final CrmRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<CrmMe> me() async {
    await ensureOnline();
    return _remote.me();
  }

  Future<CrmSetup> setup() async {
    await ensureOnline();
    return _remote.setup();
  }

  Future<CrmHome> home() async {
    await ensureOnline();
    return _remote.home();
  }

  Future<CrmNextLead> next({CrmBucket? bucket, String? idempotencyKey}) async {
    await ensureOnline();
    return _remote.next(bucket: bucket, idempotencyKey: idempotencyKey);
  }

  Future<bool> setBreak(bool onBreak,
      {String? reason, String? idempotencyKey}) async {
    await ensureOnline();
    final reply = await _remote.setBreak(onBreak,
        reason: reason, idempotencyKey: idempotencyKey);
    return reply.onBreak;
  }

  Future<CrmLeadPage> myLeads(CrmBucket bucket,
      {String? cursor, int limit = 50}) async {
    await ensureOnline();
    return _remote.myLeads(bucket, cursor: cursor, limit: limit);
  }

  Future<CrmLeadDetail> lead(int leadId) async {
    await ensureOnline();
    return _remote.lead(leadId);
  }

  Future<CrmTimelinePage> timeline(int leadId,
      {String? cursor, int limit = 50}) async {
    await ensureOnline();
    return _remote.timeline(leadId, cursor: cursor, limit: limit);
  }

  Future<CrmLookupResult> lookup(String phone, {String? idempotencyKey}) async {
    await ensureOnline();
    return _remote.lookup(phone, idempotencyKey: idempotencyKey);
  }

  Future<CrmAddLeadResult> addLead({
    required String name,
    required String phone,
    required String source,
    required int campaignId,
    String? altPhone,
    String? idempotencyKey,
  }) async {
    await ensureOnline();
    return _remote.addLead(
      name: name,
      phone: phone,
      source: source,
      campaignId: campaignId,
      altPhone: altPhone,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<CrmStartedCall> startCall(int leadId,
      {String origin = 'dialer', String? idempotencyKey}) async {
    await ensureOnline();
    return _remote.startCall(leadId,
        origin: origin, idempotencyKey: idempotencyKey);
  }

  Future<String> dial(int callId) async {
    await ensureOnline();
    return _remote.dial(callId);
  }

  Future<CrmDisposeResult> dispose(int callId, CrmDispositionDraft draft,
      {String? idempotencyKey}) async {
    await ensureOnline();
    return _remote.dispose(callId, draft, idempotencyKey: idempotencyKey);
  }

  Future<List<CrmFollowup>> followups({
    required DateTime from,
    required DateTime to,
  }) async {
    await ensureOnline();
    return _remote.followups(from: from, to: to);
  }

  Future<CrmAddLeadResult> addReference(
    int leadId, {
    required String name,
    required String phone,
    String? idempotencyKey,
  }) async {
    await ensureOnline();
    return _remote.addReference(leadId,
        name: name, phone: phone, idempotencyKey: idempotencyKey);
  }

  Future<void> transferToMe(int leadId, {String? idempotencyKey}) async {
    await ensureOnline();
    return _remote.transferToMe(leadId, idempotencyKey: idempotencyKey);
  }

  Future<List<CrmWaTemplate>> waTemplates() async {
    await ensureOnline();
    return _remote.waTemplates();
  }

  Future<void> sendWhatsapp(int leadId,
      {required int templateId, String? idempotencyKey}) async {
    await ensureOnline();
    return _remote.sendWhatsapp(leadId,
        templateId: templateId, idempotencyKey: idempotencyKey);
  }

  // ── sales quiz (#152) ───────────────────────────────────────────────────
  Future<QuizCurrent> quizCurrent() async {
    await ensureOnline();
    return _remote.quizCurrent();
  }

  Future<({QuizCurrent? data, Failure? failure})> quizCurrentSafe() async {
    try {
      await ensureOnline();
      return await _remote.quizCurrentSafe();
    } on Failure catch (failure) {
      return (data: null, failure: failure);
    } catch (_) {
      return (data: null, failure: const UnknownFailure());
    }
  }

  Future<QuizOpened> quizOpen(int roundId, {String? idempotencyKey}) async {
    await ensureOnline();
    return _remote.quizOpen(roundId, idempotencyKey: idempotencyKey);
  }

  Future<QuizAnswerResult> quizAnswer(int roundId, int choice,
      {String? idempotencyKey}) async {
    await ensureOnline();
    return _remote.quizAnswer(roundId, choice, idempotencyKey: idempotencyKey);
  }

  Future<QuizMe> quizMe() async {
    await ensureOnline();
    return _remote.quizMe();
  }

  Future<QuizResults> quizResults({
    required String from,
    required String to,
    String? userId,
  }) async {
    await ensureOnline();
    return _remote.quizResults(from: from, to: to, userId: userId);
  }
}

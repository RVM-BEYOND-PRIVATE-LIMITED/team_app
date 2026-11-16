import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/crm_repository.dart';
import '../../../domain/crm_models.dart';

// ── Home ──────────────────────────────────────────────────────────────────

sealed class CrmHomeEvent {
  const CrmHomeEvent();
}

class CrmHomeLoadRequested extends CrmHomeEvent {
  const CrmHomeLoadRequested();
}

class CrmHomeRefreshed extends CrmHomeEvent {
  const CrmHomeRefreshed();
}

class CrmBreakToggled extends CrmHomeEvent {
  const CrmBreakToggled(this.onBreak);
  final bool onBreak;
}

class CrmAutoDialToggled extends CrmHomeEvent {
  const CrmAutoDialToggled(this.on);
  final bool on;
}

class CrmHomeState extends Equatable {
  const CrmHomeState({
    this.loading = false,
    this.home,
    this.failure,
    this.busy = false,
    this.message,
    this.autoDial = false,
  });

  final bool loading;
  final CrmHome? home;
  final Failure? failure;
  final bool busy;
  final String? message;
  final bool autoDial;

  CrmHomeState copyWith({
    bool? loading,
    CrmHome? home,
    Failure? failure,
    bool? busy,
    String? message,
    bool clearMessage = false,
    bool clearFailure = false,
    bool? autoDial,
  }) =>
      CrmHomeState(
        loading: loading ?? this.loading,
        home: home ?? this.home,
        failure: clearFailure ? null : (failure ?? this.failure),
        busy: busy ?? this.busy,
        message: clearMessage ? null : (message ?? this.message),
        autoDial: autoDial ?? this.autoDial,
      );

  @override
  List<Object?> get props => [loading, home, failure, busy, message, autoDial];
}

class CrmHomeBloc extends Bloc<CrmHomeEvent, CrmHomeState> {
  CrmHomeBloc(this._repository) : super(const CrmHomeState()) {
    on<CrmHomeLoadRequested>((_, emit) => _load(emit));
    on<CrmHomeRefreshed>((_, emit) => _load(emit));
    on<CrmBreakToggled>((event, emit) async {
      if (state.busy) return;
      emit(state.copyWith(busy: true, clearMessage: true));
      try {
        final onBreak = await _repository.setBreak(event.onBreak);
        emit(state.copyWith(
          busy: false,
          home: state.home?.copyWith(onBreak: onBreak),
          message: onBreak ? 'You are on a break.' : 'You are back in the queue.',
        ));
      } on Failure catch (failure) {
        emit(state.copyWith(busy: false, failure: failure));
      }
    });
    on<CrmAutoDialToggled>((event, emit) =>
        emit(state.copyWith(autoDial: event.on)));
  }

  final CrmRepository _repository;

  Future<void> _load(Emitter<CrmHomeState> emit) async {
    emit(state.copyWith(loading: true, clearFailure: true));
    try {
      final home = await _repository.home();
      emit(state.copyWith(
        loading: false,
        home: home,
        autoDial: home.autoDial,
      ));
    } on Failure catch (failure) {
      emit(state.copyWith(loading: false, failure: failure));
    }
  }
}

// ── My Leads ──────────────────────────────────────────────────────────────

sealed class CrmLeadsEvent {
  const CrmLeadsEvent();
}

class CrmLeadsLoadRequested extends CrmLeadsEvent {
  const CrmLeadsLoadRequested();
}

class CrmLeadsRefreshed extends CrmLeadsEvent {
  const CrmLeadsRefreshed();
}

class CrmLeadsBucketSelected extends CrmLeadsEvent {
  const CrmLeadsBucketSelected(this.bucket);
  final CrmBucket bucket;
}

class CrmLeadsState extends Equatable {
  const CrmLeadsState({
    this.loading = false,
    this.bucket = CrmBucket.all,
    this.byBucket = const {},
    this.failure,
  });

  final bool loading;
  final CrmBucket bucket;
  final Map<CrmBucket, List<CrmLeadSummary>> byBucket;
  final Failure? failure;

  List<CrmLeadSummary> get leads => byBucket[bucket] ?? const [];

  int count(CrmBucket bucket) => byBucket[bucket]?.length ?? 0;

  @override
  List<Object?> get props => [loading, bucket, byBucket, failure];
}

class CrmLeadsBloc extends Bloc<CrmLeadsEvent, CrmLeadsState> {
  CrmLeadsBloc(this._repository) : super(const CrmLeadsState()) {
    on<CrmLeadsLoadRequested>((_, emit) => _load(emit));
    on<CrmLeadsRefreshed>((_, emit) => _load(emit));
    on<CrmLeadsBucketSelected>(
        (event, emit) => emit(CrmLeadsState(
              loading: state.loading,
              bucket: event.bucket,
              byBucket: state.byBucket,
              failure: state.failure,
            )));
  }

  final CrmRepository _repository;

  Future<void> _load(Emitter<CrmLeadsState> emit) async {
    emit(CrmLeadsState(
        loading: true, bucket: state.bucket, byBucket: state.byBucket));
    try {
      final results = await Future.wait([
        for (final bucket in CrmBucket.values) _repository.myLeads(bucket),
      ]);
      emit(CrmLeadsState(
        loading: false,
        bucket: state.bucket,
        byBucket: {
          for (var i = 0; i < CrmBucket.values.length; i++)
            CrmBucket.values[i]: results[i].leads,
        },
      ));
    } on Failure catch (failure) {
      emit(CrmLeadsState(
        loading: false,
        bucket: state.bucket,
        byBucket: state.byBucket,
        failure: failure,
      ));
    }
  }
}

// ── One lead ──────────────────────────────────────────────────────────────

sealed class CrmLeadEvent {
  const CrmLeadEvent();
}

class CrmLeadLoadRequested extends CrmLeadEvent {
  const CrmLeadLoadRequested();
}

class CrmLeadRefreshed extends CrmLeadEvent {
  const CrmLeadRefreshed();
}

class CrmLeadTransferRequested extends CrmLeadEvent {
  const CrmLeadTransferRequested();
}

class CrmLeadReferenceAdded extends CrmLeadEvent {
  const CrmLeadReferenceAdded({required this.name, required this.phone});
  final String name;
  final String phone;
}

class CrmLeadWhatsappSent extends CrmLeadEvent {
  const CrmLeadWhatsappSent(this.templateId);
  final int templateId;
}

class CrmLeadState extends Equatable {
  const CrmLeadState({
    this.loading = false,
    this.lead,
    this.timeline = const [],
    this.failure,
    this.busy = false,
    this.message,
    this.templates = const [],
  });

  final bool loading;
  final CrmLeadDetail? lead;
  final List<CrmTimelineEvent> timeline;
  final Failure? failure;
  final bool busy;
  final String? message;
  final List<CrmWaTemplate> templates;

  CrmLeadState copyWith({
    bool? loading,
    CrmLeadDetail? lead,
    List<CrmTimelineEvent>? timeline,
    Failure? failure,
    bool? busy,
    String? message,
    bool clearMessage = false,
    bool clearFailure = false,
    List<CrmWaTemplate>? templates,
  }) =>
      CrmLeadState(
        loading: loading ?? this.loading,
        lead: lead ?? this.lead,
        timeline: timeline ?? this.timeline,
        failure: clearFailure ? null : (failure ?? this.failure),
        busy: busy ?? this.busy,
        message: clearMessage ? null : (message ?? this.message),
        templates: templates ?? this.templates,
      );

  @override
  List<Object?> get props =>
      [loading, lead, timeline, failure, busy, message, templates];
}

class CrmLeadBloc extends Bloc<CrmLeadEvent, CrmLeadState> {
  CrmLeadBloc(this._repository, this.leadId) : super(const CrmLeadState()) {
    on<CrmLeadLoadRequested>((_, emit) => _load(emit));
    on<CrmLeadRefreshed>((_, emit) => _load(emit));
    on<CrmLeadTransferRequested>((_, emit) => _transfer(emit));
    on<CrmLeadReferenceAdded>((event, emit) =>
        _reference(emit, event.name, event.phone));
    on<CrmLeadWhatsappSent>((event, emit) async {
      if (state.busy) return;
      emit(state.copyWith(busy: true, clearMessage: true));
      try {
        await _repository.sendWhatsapp(leadId,
            templateId: event.templateId,
            idempotencyKey: IdempotencyInterceptor.newKey());
        emit(state.copyWith(busy: false, message: 'WhatsApp queued.'));
      } on Failure catch (failure) {
        emit(state.copyWith(busy: false, failure: failure));
      }
    });
  }

  final CrmRepository _repository;
  final int leadId;

  Future<void> _load(Emitter<CrmLeadState> emit) async {
    emit(state.copyWith(loading: true, clearFailure: true));
    try {
      final lead = await _repository.lead(leadId);
      final timeline = await _repository.timeline(leadId);
      List<CrmWaTemplate> templates = const [];
      try {
        templates = await _repository.waTemplates();
      } catch (_) {
        templates = const [];
      }
      emit(state.copyWith(
        loading: false,
        lead: lead,
        timeline: timeline.events,
        templates: templates,
      ));
    } on Failure catch (failure) {
      emit(state.copyWith(loading: false, failure: failure));
    }
  }

  Future<void> _transfer(Emitter<CrmLeadState> emit) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, clearMessage: true, clearFailure: true));
    try {
      await _repository.transferToMe(leadId,
          idempotencyKey: IdempotencyInterceptor.newKey());
      final lead = await _repository.lead(leadId);
      emit(state.copyWith(
          busy: false, lead: lead, message: 'This lead is yours now.'));
    } on Failure catch (failure) {
      emit(state.copyWith(busy: false, failure: failure));
    }
  }

  Future<void> _reference(
      Emitter<CrmLeadState> emit, String name, String phone) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, clearMessage: true, clearFailure: true));
    try {
      final result = await _repository.addReference(leadId,
          name: name,
          phone: phone,
          idempotencyKey: IdempotencyInterceptor.newKey());
      emit(state.copyWith(
        busy: false,
        message: result.existed
            ? 'That number is already on file.'
            : 'Reference added.',
      ));
    } on Failure catch (failure) {
      emit(state.copyWith(busy: false, failure: failure));
    }
  }
}

// ── Disposition ───────────────────────────────────────────────────────────

sealed class CrmDispositionEvent {
  const CrmDispositionEvent();
}

class CrmDispositionConnected extends CrmDispositionEvent {
  const CrmDispositionConnected(this.connected);
  final bool connected;
}

class CrmDispositionStage extends CrmDispositionEvent {
  const CrmDispositionStage(this.stage);
  final CrmStage stage;
}

class CrmDispositionTag extends CrmDispositionEvent {
  const CrmDispositionTag(this.tagId);
  final int? tagId;
}

class CrmDispositionRemark extends CrmDispositionEvent {
  const CrmDispositionRemark(this.remark);
  final String remark;
}

class CrmDispositionScript extends CrmDispositionEvent {
  const CrmDispositionScript({
    this.education,
    this.workExperience,
    this.coursePackage,
  });
  final String? education;
  final String? workExperience;
  final String? coursePackage;
}

class CrmDispositionFollowup extends CrmDispositionEvent {
  const CrmDispositionFollowup(this.at);
  final DateTime? at;
}

class CrmDispositionReason extends CrmDispositionEvent {
  const CrmDispositionReason(this.code);
  final String code;
}

class CrmDispositionNextTry extends CrmDispositionEvent {
  const CrmDispositionNextTry(this.code);
  final String code;
}

class CrmDispositionSubmit extends CrmDispositionEvent {
  const CrmDispositionSubmit();
}

class CrmDispositionState extends Equatable {
  const CrmDispositionState({
    required this.draft,
    this.submitting = false,
    this.failure,
    this.message,
    this.result,
    this.saved = false,
  });

  final CrmDispositionDraft draft;
  final bool submitting;
  final Failure? failure;
  final String? message;
  final CrmDisposeResult? result;
  final bool saved;

  CrmDispositionState copyWith({
    CrmDispositionDraft? draft,
    bool? submitting,
    Failure? failure,
    String? message,
    bool clearMessage = false,
    bool clearFailure = false,
    CrmDisposeResult? result,
    bool? saved,
  }) =>
      CrmDispositionState(
        draft: draft ?? this.draft,
        submitting: submitting ?? this.submitting,
        failure: clearFailure ? null : (failure ?? this.failure),
        message: clearMessage ? null : (message ?? this.message),
        result: result ?? this.result,
        saved: saved ?? this.saved,
      );

  @override
  List<Object?> get props =>
      [draft, submitting, failure, message, result, saved];
}

class CrmDispositionBloc
    extends Bloc<CrmDispositionEvent, CrmDispositionState> {
  CrmDispositionBloc({
    required CrmRepository repository,
    required this.setup,
    required this.callId,
    required this.lead,
    required String remarkIdempotencyKey,
  })  : _repository = repository,
        _key = remarkIdempotencyKey,
        super(CrmDispositionState(
          draft: CrmDispositionDraft(
            stageId: lead.summary.stageId,
            stageIsFinal: lead.summary.stageKind.isFinal,
          ),
        )) {
    on<CrmDispositionConnected>((event, emit) {
      emit(state.copyWith(
        draft: state.draft.copyWith(
          connected: event.connected,
          clearFollowup: !event.connected,
        ),
        clearFailure: true,
        clearMessage: true,
      ));
    });
    on<CrmDispositionStage>((event, emit) {
      final finalStage = event.stage.kind.isFinal;
      emit(state.copyWith(
        draft: state.draft.copyWith(
          stageId: event.stage.id,
          stageIsFinal: finalStage,
          // The server refuses a tag from another stage; a final stage also
          // needs no follow-up.
          tagId: null,
          clearFollowup: finalStage,
        ),
      ));
    });
    on<CrmDispositionTag>((event, emit) => emit(state.copyWith(
        draft: state.draft.copyWith(tagId: event.tagId))));
    on<CrmDispositionRemark>((event, emit) => emit(state.copyWith(
        draft: state.draft.copyWith(remark: event.remark))));
    on<CrmDispositionScript>((event, emit) => emit(state.copyWith(
          draft: state.draft.copyWith(
            education: event.education,
            workExperience: event.workExperience,
            coursePackage: event.coursePackage,
          ),
        )));
    on<CrmDispositionFollowup>((event, emit) => emit(state.copyWith(
        draft: state.draft.copyWith(
            nextFollowupAt: event.at, clearFollowup: event.at == null))));
    on<CrmDispositionReason>((event, emit) => emit(state.copyWith(
        draft: state.draft.copyWith(reason: event.code))));
    on<CrmDispositionNextTry>((event, emit) => emit(state.copyWith(
        draft: state.draft.copyWith(nextTry: event.code))));
    on<CrmDispositionSubmit>((_, emit) => _submit(emit));
  }

  final CrmRepository _repository;
  final CrmSetup setup;
  final int callId;
  final CrmLeadDetail lead;
  final String _key;

  Future<void> _submit(Emitter<CrmDispositionState> emit) async {
    if (state.submitting || state.saved) return;
    final problem = state.draft.validate();
    if (problem != null) {
      emit(state.copyWith(failure: UnknownFailure(problem)));
      return;
    }
    emit(state.copyWith(
        submitting: true, clearFailure: true, clearMessage: true));
    try {
      final result = await _repository.dispose(callId, state.draft,
          idempotencyKey: _key);
      emit(state.copyWith(
        submitting: false,
        saved: true,
        result: result,
        message: result.closedBySystem
            ? 'Saved. The system closed this lead after its last retry.'
            : 'Saved.',
      ));
    } on Failure catch (failure) {
      emit(state.copyWith(submitting: false, failure: failure));
    }
  }
}

// ── Calendar ──────────────────────────────────────────────────────────────

sealed class CrmCalendarEvent {
  const CrmCalendarEvent();
}

class CrmCalendarLoadRequested extends CrmCalendarEvent {
  const CrmCalendarLoadRequested();
}

class CrmCalendarRefreshed extends CrmCalendarEvent {
  const CrmCalendarRefreshed();
}

class CrmCalendarState extends Equatable {
  const CrmCalendarState({
    this.loading = false,
    this.followups = const [],
    this.failure,
  });

  final bool loading;
  final List<CrmFollowup> followups;
  final Failure? failure;

  @override
  List<Object?> get props => [loading, followups, failure];
}

class CrmCalendarBloc extends Bloc<CrmCalendarEvent, CrmCalendarState> {
  CrmCalendarBloc(this._repository) : super(const CrmCalendarState()) {
    on<CrmCalendarLoadRequested>((_, emit) => _load(emit));
    on<CrmCalendarRefreshed>((_, emit) => _load(emit));
  }

  final CrmRepository _repository;

  Future<void> _load(Emitter<CrmCalendarState> emit) async {
    emit(CrmCalendarState(loading: true, followups: state.followups));
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - DateTime.monday));
    final end = start.add(const Duration(days: 6));
    try {
      final followups =
          await _repository.followups(from: start, to: end);
      emit(CrmCalendarState(loading: false, followups: followups));
    } on Failure catch (failure) {
      emit(CrmCalendarState(
          loading: false, followups: state.followups, failure: failure));
    }
  }
}

// ── Add lead ──────────────────────────────────────────────────────────────

sealed class CrmAddLeadEvent {
  const CrmAddLeadEvent();
}

class CrmAddLeadSource extends CrmAddLeadEvent {
  const CrmAddLeadSource(this.source);
  final String source;
}

class CrmAddLeadCampaign extends CrmAddLeadEvent {
  const CrmAddLeadCampaign(this.campaignId);
  final int campaignId;
}

class CrmAddLeadSubmit extends CrmAddLeadEvent {
  const CrmAddLeadSubmit({
    required this.name,
    required this.phone,
    this.altPhone,
  });
  final String name;
  final String phone;
  final String? altPhone;
}

class CrmAddLeadState extends Equatable {
  const CrmAddLeadState({
    this.source = 'manual',
    this.campaignId,
    this.submitting = false,
    this.failure,
    this.result,
  });

  final String source;
  final int? campaignId;
  final bool submitting;
  final Failure? failure;
  final CrmAddLeadResult? result;

  CrmAddLeadState copyWith({
    String? source,
    int? campaignId,
    bool? submitting,
    Failure? failure,
    CrmAddLeadResult? result,
  }) =>
      CrmAddLeadState(
        source: source ?? this.source,
        campaignId: campaignId ?? this.campaignId,
        submitting: submitting ?? this.submitting,
        failure: failure ?? this.failure,
        result: result ?? this.result,
      );

  @override
  List<Object?> get props => [source, campaignId, submitting, failure, result];
}

class CrmAddLeadBloc extends Bloc<CrmAddLeadEvent, CrmAddLeadState> {
  CrmAddLeadBloc(this._repository, this.setup) : super(const CrmAddLeadState()) {
    on<CrmAddLeadSource>(
        (event, emit) => emit(state.copyWith(source: event.source)));
    on<CrmAddLeadCampaign>((event, emit) =>
        emit(state.copyWith(campaignId: event.campaignId)));
    on<CrmAddLeadSubmit>((event, emit) async {
      if (state.submitting) return;
      final campaignId = state.campaignId ??
          (setup.campaigns.isEmpty ? null : setup.campaigns.first.id);
      if (campaignId == null) {
        emit(state.copyWith(
            failure: const UnknownFailure('No campaign is set up yet.')));
        return;
      }
      emit(state.copyWith(submitting: true, failure: null));
      try {
        final result = await _repository.addLead(
          name: event.name.trim(),
          phone: event.phone,
          altPhone: event.altPhone,
          source: state.source,
          campaignId: campaignId,
          idempotencyKey: IdempotencyInterceptor.newKey(),
        );
        emit(state.copyWith(submitting: false, result: result));
      } on Failure catch (failure) {
        emit(state.copyWith(submitting: false, failure: failure));
      }
    });
  }

  final CrmRepository _repository;
  final CrmSetup setup;
}

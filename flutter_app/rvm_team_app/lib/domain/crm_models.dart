import 'package:equatable/equatable.dart';

/// The Sales CRM in the Team app (team_app #51). The shapes come from the
/// Scheduler's `contracts/crm.openapi.yaml`; no phone number is kept except
/// the one returned by a start-call reply, which is passed straight to the
/// dialer and never stored here.
enum CrmBucket {
  all('all', 'All'),
  uncontacted('uncontacted', 'Not called'),
  inProgress('in_progress', 'In progress'),
  followUp('follow_up', 'Follow-ups'),
  notConnected('not_connected', 'Not connected');

  const CrmBucket(this.wire, this.label);

  final String wire;
  final String label;
}

enum CrmStageKind {
  open,
  notConnected,
  inProgress,
  converted,
  lost;

  static CrmStageKind parse(Object? value) => switch (value) {
        'not_connected' => CrmStageKind.notConnected,
        'in_progress' => CrmStageKind.inProgress,
        'converted' => CrmStageKind.converted,
        'lost' => CrmStageKind.lost,
        _ => CrmStageKind.open,
      };

  bool get isFinal =>
      this == CrmStageKind.converted || this == CrmStageKind.lost;
}

class CrmUserRef extends Equatable {
  const CrmUserRef({required this.userId, required this.name});

  final String userId;
  final String name;

  static CrmUserRef? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = value['user_id'];
    if (id is! String || id.isEmpty) return null;
    return CrmUserRef(
        userId: id, name: (value['name'] ?? 'Unknown').toString());
  }

  @override
  List<Object?> get props => [userId, name];
}

class CrmTag extends Equatable {
  const CrmTag({required this.id, required this.name});

  final int id;
  final String name;

  static CrmTag? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = _int(value['id']);
    if (id == null) return null;
    return CrmTag(id: id, name: (value['name'] ?? '').toString());
  }

  @override
  List<Object?> get props => [id, name];
}

class CrmStage extends Equatable {
  const CrmStage({
    required this.id,
    required this.name,
    required this.kind,
    required this.position,
    required this.tags,
  });

  final int id;
  final String name;
  final CrmStageKind kind;
  final int position;
  final List<CrmTag> tags;

  bool get isFinal => kind.isFinal;

  static CrmStage? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = _int(value['id']);
    if (id == null) return null;
    return CrmStage(
      id: id,
      name: (value['name'] ?? '').toString(),
      kind: CrmStageKind.parse(value['kind']),
      position: _int(value['position']) ?? 0,
      tags: [
        for (final tag in (value['tags'] as List? ?? const []))
          if (CrmTag.tryParse(tag) case final parsed?) parsed,
      ],
    );
  }

  @override
  List<Object?> get props => [id, name, kind, position, tags];
}

class CrmCampaign extends Equatable {
  const CrmCampaign({
    required this.id,
    required this.name,
    required this.priority,
    required this.distribution,
    required this.paused,
  });

  final int id;
  final String name;
  final int priority;
  final String distribution;
  final bool paused;

  static CrmCampaign? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = _int(value['id']);
    if (id == null) return null;
    return CrmCampaign(
      id: id,
      name: (value['name'] ?? '').toString(),
      priority: _int(value['priority']) ?? 0,
      distribution: (value['distribution'] ?? '').toString(),
      paused: value['paused'] == true,
    );
  }

  @override
  List<Object?> get props => [id, name, priority, distribution, paused];
}

class CrmProperty extends Equatable {
  const CrmProperty({
    required this.key,
    required this.label,
    required this.type,
    required this.position,
  });

  final String key;
  final String label;
  final String type;
  final int position;

  static CrmProperty? tryParse(Object? value) {
    if (value is! Map) return null;
    final key = value['key'];
    if (key is! String || key.isEmpty) return null;
    return CrmProperty(
      key: key,
      label: (value['label'] ?? key).toString(),
      type: (value['type'] ?? 'text').toString(),
      position: _int(value['position']) ?? 0,
    );
  }

  @override
  List<Object?> get props => [key, label, type, position];
}

class CrmReason extends Equatable {
  const CrmReason({
    required this.code,
    required this.label,
    required this.retries,
    required this.gapMinutes,
    required this.closesAtOnce,
  });

  final String code;
  final String label;
  final int retries;
  final int gapMinutes;
  final bool closesAtOnce;

  static CrmReason? tryParse(Object? value) {
    if (value is! Map) return null;
    final code = value['code'];
    if (code is! String || code.isEmpty) return null;
    return CrmReason(
      code: code,
      label: (value['label'] ?? code).toString(),
      retries: _int(value['retries']) ?? 0,
      gapMinutes: _int(value['gap_minutes']) ?? 0,
      closesAtOnce: value['closes_at_once'] == true,
    );
  }

  @override
  List<Object?> get props => [code, label, retries, gapMinutes, closesAtOnce];
}

class CrmFollowupPreset extends Equatable {
  const CrmFollowupPreset({required this.code, required this.minutes});

  final String code;
  final int minutes;

  String get label => switch (code) {
        '1h' => '1 hour',
        '6h' => '6 hours',
        '1d' => '1 day',
        _ => code,
      };

  static CrmFollowupPreset? tryParse(Object? value) {
    if (value is! Map) return null;
    final code = value['code'];
    if (code is! String || code.isEmpty) return null;
    return CrmFollowupPreset(code: code, minutes: _int(value['minutes']) ?? 0);
  }

  @override
  List<Object?> get props => [code, minutes];
}

class CrmSetup extends Equatable {
  const CrmSetup({
    required this.pipelineId,
    required this.pipelineName,
    required this.stages,
    required this.moves,
    required this.campaigns,
    required this.properties,
    required this.reasons,
    required this.followupPresets,
    required this.webCallMode,
    required this.autoDialDefault,
    required this.formAlertMinutes,
  });

  final int pipelineId;
  final String pipelineName;
  final List<CrmStage> stages;
  final List<({int from, int to})> moves;
  final List<CrmCampaign> campaigns;
  final List<CrmProperty> properties;
  final List<CrmReason> reasons;
  final List<CrmFollowupPreset> followupPresets;
  final String webCallMode;
  final bool autoDialDefault;
  final int formAlertMinutes;

  CrmStage? stage(int id) {
    for (final s in stages) {
      if (s.id == id) return s;
    }
    return null;
  }

  CrmReason? reason(String code) {
    for (final r in reasons) {
      if (r.code == code) return r;
    }
    return null;
  }

  CrmFollowupPreset? preset(String code) {
    for (final p in followupPresets) {
      if (p.code == code) return p;
    }
    return null;
  }

  /// The stages the server allows after [fromStageId]. The lead's current
  /// stage is always offered, so a disposition can keep it unchanged.
  List<CrmStage> nextStages(int fromStageId) {
    final allowed = <int>{fromStageId};
    for (final move in moves) {
      if (move.from == fromStageId) allowed.add(move.to);
    }
    return [
      for (final stage in stages)
        if (allowed.contains(stage.id)) stage,
    ];
  }

  static CrmSetup fromJson(Map<String, dynamic> json) {
    final stages = [
      for (final s in (json['stages'] as List? ?? const []))
        if (CrmStage.tryParse(s) case final parsed?) parsed,
    ];
    final moves = [
      for (final m in (json['moves'] as List? ?? const []))
        if (m is Map)
          if ((_int(m['from_stage_id']), _int(m['to_stage_id']))
              case (final int from, final int to))
            (from: from, to: to),
    ];
    final settings = json['settings'] is Map
        ? (json['settings'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final pipeline = json['pipeline'] is Map
        ? (json['pipeline'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return CrmSetup(
      pipelineId: _int(pipeline['id']) ?? 0,
      pipelineName: (pipeline['name'] ?? 'Sales').toString(),
      stages: stages,
      moves: moves,
      campaigns: [
        for (final c in (json['campaigns'] as List? ?? const []))
          if (CrmCampaign.tryParse(c) case final parsed?) parsed,
      ],
      properties: [
        for (final p in (json['properties'] as List? ?? const []))
          if (CrmProperty.tryParse(p) case final parsed?) parsed,
      ],
      reasons: [
        for (final r in (json['not_connected_reasons'] as List? ?? const []))
          if (CrmReason.tryParse(r) case final parsed?) parsed,
      ],
      followupPresets: [
        for (final p in (json['followup_presets'] as List? ?? const []))
          if (CrmFollowupPreset.tryParse(p) case final parsed?) parsed,
      ],
      webCallMode: (settings['web_call_mode'] ?? 'push').toString(),
      autoDialDefault: settings['auto_dial_default'] == true,
      formAlertMinutes: _int(settings['form_alert_minutes']) ?? 10,
    );
  }

  @override
  List<Object?> get props => [
        pipelineId,
        pipelineName,
        stages,
        moves,
        campaigns,
        properties,
        reasons,
        followupPresets,
        webCallMode,
        autoDialDefault,
        formAlertMinutes,
      ];
}

class CrmMe extends Equatable {
  const CrmMe({
    required this.userId,
    required this.name,
    required this.level,
    required this.capabilities,
    required this.allCampaigns,
    required this.onBreak,
    required this.openCallId,
  });

  final String userId;
  final String name;
  final String level;
  final Set<String> capabilities;
  final bool allCampaigns;
  final bool onBreak;
  final int? openCallId;

  bool can(String capability) => capabilities.contains(capability);

  static CrmMe fromJson(Map<String, dynamic> json) {
    final scope = json['scope'] is Map
        ? (json['scope'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final state = json['state'] is Map
        ? (json['state'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return CrmMe(
      userId: (json['user_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      level: (json['level'] ?? 'counsellor').toString(),
      capabilities: {
        for (final c in (json['capabilities'] as List? ?? const []))
          c.toString(),
      },
      allCampaigns: scope['all'] == true,
      onBreak: state['on_break'] == true,
      openCallId: _int(state['open_call_id']),
    );
  }

  @override
  List<Object?> get props =>
      [userId, name, level, capabilities, allCampaigns, onBreak, openCallId];
}

class CrmOpenCall extends Equatable {
  const CrmOpenCall({
    required this.callId,
    required this.leadId,
    required this.leadName,
    required this.startedAt,
  });

  final int callId;
  final int leadId;
  final String leadName;
  final DateTime? startedAt;

  static CrmOpenCall? tryParse(Object? value) {
    if (value is! Map) return null;
    final callId = _int(value['call_id']);
    final leadId = _int(value['lead_id']);
    if (callId == null || leadId == null) return null;
    return CrmOpenCall(
      callId: callId,
      leadId: leadId,
      leadName: (value['lead_name'] ?? 'Lead').toString(),
      startedAt: _date(value['started_at']),
    );
  }

  @override
  List<Object?> get props => [callId, leadId, leadName, startedAt];
}

class CrmHome extends Equatable {
  const CrmHome({
    required this.followupsDueToday,
    required this.missed,
    required this.callbacksWaiting,
    required this.openCall,
    required this.onBreak,
    required this.autoDial,
  });

  final int followupsDueToday;
  final int missed;
  final int callbacksWaiting;
  final CrmOpenCall? openCall;
  final bool onBreak;
  final bool autoDial;

  CrmHome copyWith({bool? onBreak, bool? autoDial, CrmOpenCall? openCall}) =>
      CrmHome(
        followupsDueToday: followupsDueToday,
        missed: missed,
        callbacksWaiting: callbacksWaiting,
        openCall: openCall ?? this.openCall,
        onBreak: onBreak ?? this.onBreak,
        autoDial: autoDial ?? this.autoDial,
      );

  static CrmHome fromJson(Map<String, dynamic> json) {
    final counts = json['counts'] is Map
        ? (json['counts'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return CrmHome(
      followupsDueToday: _int(counts['followups_due_today']) ?? 0,
      missed: _int(counts['missed']) ?? 0,
      callbacksWaiting: _int(counts['callbacks_waiting']) ?? 0,
      openCall: CrmOpenCall.tryParse(json['open_call']),
      onBreak: json['on_break'] == true,
      autoDial: json['auto_dial'] == true,
    );
  }

  @override
  List<Object?> get props => [
        followupsDueToday,
        missed,
        callbacksWaiting,
        openCall,
        onBreak,
        autoDial,
      ];
}

class CrmLeadSummary extends Equatable {
  const CrmLeadSummary({
    required this.id,
    required this.name,
    required this.phoneMasked,
    required this.campaignName,
    required this.stageId,
    required this.stageName,
    required this.stageKind,
    required this.tagName,
    required this.ownerName,
    required this.status,
    required this.nextFollowupAt,
    required this.attempts,
    required this.lastContactAt,
    required this.latestRemark,
    required this.source,
  });

  final int id;
  final String name;
  final String phoneMasked;
  final String campaignName;
  final int stageId;
  final String stageName;
  final CrmStageKind stageKind;
  final String? tagName;
  final String? ownerName;
  final String status;
  final DateTime? nextFollowupAt;
  final int attempts;
  final DateTime? lastContactAt;
  final String? latestRemark;
  final String source;

  bool get overdue =>
      nextFollowupAt != null && nextFollowupAt!.isBefore(DateTime.now());

  static CrmLeadSummary? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = _int(value['id']);
    if (id == null) return null;
    final campaign = value['campaign'] is Map
        ? (value['campaign'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final stage = value['stage'] is Map
        ? (value['stage'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final owner = CrmUserRef.tryParse(value['owner']);
    final tag = CrmTag.tryParse(value['tag']);
    return CrmLeadSummary(
      id: id,
      name: (value['name'] ?? 'Lead').toString(),
      phoneMasked: (value['phone_masked'] ?? '').toString(),
      campaignName: (campaign['name'] ?? '').toString(),
      stageId: _int(stage['id']) ?? 0,
      stageName: (stage['name'] ?? '').toString(),
      stageKind: CrmStageKind.parse(stage['kind']),
      tagName: tag?.name,
      ownerName: owner?.name,
      status: (value['status'] ?? '').toString(),
      nextFollowupAt: _date(value['next_followup_at']),
      attempts: _int(value['attempts']) ?? 0,
      lastContactAt: _date(value['last_contact_at']),
      latestRemark: value['latest_remark']?.toString(),
      source: (value['source'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        phoneMasked,
        campaignName,
        stageId,
        stageName,
        stageKind,
        tagName,
        ownerName,
        status,
        nextFollowupAt,
        attempts,
        lastContactAt,
        latestRemark,
        source,
      ];
}

class CrmLeadDetail extends Equatable {
  const CrmLeadDetail({
    required this.summary,
    required this.altPhoneMasked,
    required this.properties,
    required this.createdAt,
    required this.assignedAt,
    required this.whatsappOptOut,
    required this.referrerLeadId,
    required this.openCallId,
  });

  final CrmLeadSummary summary;
  final String? altPhoneMasked;
  final Map<String, String> properties;
  final DateTime? createdAt;
  final DateTime? assignedAt;
  final bool whatsappOptOut;
  final int? referrerLeadId;
  final int? openCallId;

  int get id => summary.id;

  static CrmLeadDetail? tryParse(Object? value) {
    final summary = CrmLeadSummary.tryParse(value);
    if (summary == null || value is! Map) return null;
    final rawProps = value['props'];
    return CrmLeadDetail(
      summary: summary,
      altPhoneMasked: value['alt_phone_masked']?.toString(),
      properties: {
        if (rawProps is Map)
          for (final entry in rawProps.entries)
            entry.key.toString(): entry.value?.toString() ?? '',
      },
      createdAt: _date(value['created_at']),
      assignedAt: _date(value['assigned_at']),
      whatsappOptOut: value['whatsapp_opt_out'] == true,
      referrerLeadId: _int(value['referrer_lead_id']),
      openCallId: _int(value['open_call_id']),
    );
  }

  @override
  List<Object?> get props => [
        summary,
        altPhoneMasked,
        properties,
        createdAt,
        assignedAt,
        whatsappOptOut,
        referrerLeadId,
        openCallId,
      ];
}

class CrmLeadPage extends Equatable {
  const CrmLeadPage({required this.leads, required this.next});

  final List<CrmLeadSummary> leads;
  final String? next;

  static CrmLeadPage fromJson(Map<String, dynamic> json) => CrmLeadPage(
        leads: [
          for (final lead in (json['leads'] as List? ?? const []))
            if (CrmLeadSummary.tryParse(lead) case final parsed?) parsed,
        ],
        next: json['next']?.toString(),
      );

  @override
  List<Object?> get props => [leads, next];
}

class CrmTimelineEvent extends Equatable {
  const CrmTimelineEvent({
    required this.id,
    required this.type,
    required this.at,
    required this.actorName,
    required this.payload,
  });

  final int id;
  final String type;
  final DateTime? at;
  final String? actorName;
  final Map<String, dynamic> payload;

  String get label {
    final stage = payload['stage']?.toString();
    final reason = payload['reason']?.toString();
    final remark = payload['remark']?.toString();
    return switch (type) {
      'created' => 'Lead created',
      'merged' => 'Number already on file',
      'assigned' => 'Assigned',
      'transferred' => 'Transferred',
      'call_started' => 'Call started',
      'number_revealed' => 'Number opened',
      'disposed' => 'Call saved${stage == null ? '' : ' · $stage'}',
      'stage_changed' => 'Stage changed${stage == null ? '' : ' · $stage'}',
      'tag_changed' => 'Tag changed',
      'followup_set' => 'Follow-up set',
      'remark' => remark ?? 'Remark added',
      'reference_added' => 'Reference added',
      'closed_by_system' =>
        'Closed by the system${reason == null ? '' : ' · $reason'}',
      'whatsapp_sent' => 'WhatsApp sent',
      'call_abandoned' => 'Call abandoned',
      _ => type.replaceAll('_', ' '),
    };
  }

  static CrmTimelineEvent? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = _int(value['id']);
    if (id == null) return null;
    final actor = CrmUserRef.tryParse(value['actor']);
    final payload = value['payload'] is Map
        ? (value['payload'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return CrmTimelineEvent(
      id: id,
      type: (value['type'] ?? '').toString(),
      at: _date(value['at']),
      actorName: actor?.name,
      payload: payload,
    );
  }

  @override
  List<Object?> get props => [id, type, at, actorName, payload];
}

class CrmTimelinePage extends Equatable {
  const CrmTimelinePage({required this.events, required this.next});

  final List<CrmTimelineEvent> events;
  final String? next;

  static CrmTimelinePage fromJson(Map<String, dynamic> json) =>
      CrmTimelinePage(
        events: [
          for (final e in (json['events'] as List? ?? const []))
            if (CrmTimelineEvent.tryParse(e) case final parsed?) parsed,
        ],
        next: json['next']?.toString(),
      );

  @override
  List<Object?> get props => [events, next];
}

class CrmNextLead extends Equatable {
  const CrmNextLead({required this.lead, required this.reason});

  final CrmLeadDetail? lead;
  final String reason;

  static CrmNextLead fromJson(Map<String, dynamic> json) => CrmNextLead(
        lead: CrmLeadDetail.tryParse(json['lead']),
        reason: (json['reason'] ?? 'empty').toString(),
      );

  @override
  List<Object?> get props => [lead, reason];
}

class CrmStartedCall extends Equatable {
  const CrmStartedCall({
    required this.callId,
    required this.leadId,
    required this.startedAt,
    required this.mode,
    required this.phone,
  });

  final int callId;
  final int leadId;
  final DateTime? startedAt;
  final String mode;

  /// The number returned once by the start-call reply. It is held only until
  /// the dialer takes it and is never put into a model kept by a screen.
  final String? phone;

  static CrmStartedCall fromJson(Map<String, dynamic> json) => CrmStartedCall(
        callId: _int(json['call_id']) ?? 0,
        leadId: _int(json['lead_id']) ?? 0,
        startedAt: _date(json['started_at']),
        mode: (json['mode'] ?? 'dial').toString(),
        phone: json['phone']?.toString(),
      );

  @override
  List<Object?> get props => [callId, leadId, startedAt, mode];
}

class CrmDisposeResult extends Equatable {
  const CrmDisposeResult({
    required this.lead,
    required this.callId,
    required this.formSeconds,
    required this.closedBySystem,
  });

  final CrmLeadDetail? lead;
  final int callId;
  final int formSeconds;
  final bool closedBySystem;

  static CrmDisposeResult fromJson(Map<String, dynamic> json) {
    final call = json['call'] is Map
        ? (json['call'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return CrmDisposeResult(
      lead: CrmLeadDetail.tryParse(json['lead']),
      callId: _int(call['id']) ?? 0,
      formSeconds: _int(call['form_seconds']) ?? 0,
      closedBySystem: json['closed_by_system'] == true,
    );
  }

  @override
  List<Object?> get props => [lead, callId, formSeconds, closedBySystem];
}

class CrmFollowup extends Equatable {
  const CrmFollowup({
    required this.leadId,
    required this.name,
    required this.phoneMasked,
    required this.at,
    required this.overdue,
    required this.stage,
    required this.tag,
  });

  final int leadId;
  final String name;
  final String phoneMasked;
  final DateTime? at;
  final bool overdue;
  final String stage;
  final String? tag;

  static CrmFollowup? tryParse(Object? value) {
    if (value is! Map) return null;
    final leadId = _int(value['lead_id']);
    if (leadId == null) return null;
    return CrmFollowup(
      leadId: leadId,
      name: (value['name'] ?? 'Lead').toString(),
      phoneMasked: (value['phone_masked'] ?? '').toString(),
      at: _date(value['next_followup_at']),
      overdue: value['overdue'] == true,
      stage: (value['stage'] ?? '').toString(),
      tag: value['tag']?.toString(),
    );
  }

  @override
  List<Object?> get props => [leadId, name, phoneMasked, at, overdue, stage, tag];
}

class CrmAddLeadResult extends Equatable {
  const CrmAddLeadResult({
    required this.lead,
    required this.existed,
    required this.ownerName,
    required this.callId,
  });

  final CrmLeadDetail? lead;
  final bool existed;
  final String? ownerName;
  final int? callId;

  static CrmAddLeadResult fromJson(Map<String, dynamic> json) =>
      CrmAddLeadResult(
        lead: CrmLeadDetail.tryParse(json['lead']),
        existed: json['existed'] == true,
        ownerName: json['owner_name']?.toString(),
        callId: _int(json['call_id']),
      );

  @override
  List<Object?> get props => [lead, existed, ownerName, callId];
}

class CrmLookupResult extends Equatable {
  const CrmLookupResult({
    required this.lead,
    required this.ownerName,
    required this.grantedUntil,
  });

  final CrmLeadDetail? lead;
  final String? ownerName;
  final DateTime? grantedUntil;

  static CrmLookupResult fromJson(Map<String, dynamic> json) => CrmLookupResult(
        lead: CrmLeadDetail.tryParse(json['lead']),
        ownerName: json['owner_name']?.toString(),
        grantedUntil: _date(json['granted_until']),
      );

  @override
  List<Object?> get props => [lead, ownerName, grantedUntil];
}

class CrmWaTemplate extends Equatable {
  const CrmWaTemplate({
    required this.id,
    required this.name,
    required this.language,
    required this.purpose,
    required this.approved,
    required this.preview,
  });

  final int id;
  final String name;
  final String language;
  final String purpose;
  final bool approved;
  final String? preview;

  static CrmWaTemplate? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = _int(value['id']);
    if (id == null) return null;
    return CrmWaTemplate(
      id: id,
      name: (value['name'] ?? '').toString(),
      language: (value['language'] ?? 'en').toString(),
      purpose: (value['purpose'] ?? '').toString(),
      approved: value['approved'] == true,
      preview: value['preview']?.toString(),
    );
  }

  @override
  List<Object?> get props => [id, name, language, purpose, approved, preview];
}

/// The disposition form's answers, and the rules the server enforces. Kept
/// out of the widget so the rules are tested without a phone.
class CrmDispositionDraft extends Equatable {
  const CrmDispositionDraft({
    this.connected,
    this.stageId,
    this.tagId,
    this.remark = '',
    this.education = '',
    this.workExperience = '',
    this.coursePackage = '',
    this.nextFollowupAt,
    this.reason,
    this.nextTry,
    this.stageIsFinal = false,
  });

  final bool? connected;
  final int? stageId;
  final int? tagId;
  final String remark;
  final String education;
  final String workExperience;
  final String coursePackage;
  final DateTime? nextFollowupAt;
  final String? reason;
  final String? nextTry;
  final bool stageIsFinal;

  CrmDispositionDraft copyWith({
    bool? connected,
    int? stageId,
    int? tagId,
    String? remark,
    String? education,
    String? workExperience,
    String? coursePackage,
    DateTime? nextFollowupAt,
    bool clearFollowup = false,
    String? reason,
    String? nextTry,
    bool? stageIsFinal,
  }) =>
      CrmDispositionDraft(
        connected: connected ?? this.connected,
        stageId: stageId ?? this.stageId,
        tagId: tagId ?? this.tagId,
        remark: remark ?? this.remark,
        education: education ?? this.education,
        workExperience: workExperience ?? this.workExperience,
        coursePackage: coursePackage ?? this.coursePackage,
        nextFollowupAt:
            clearFollowup ? null : (nextFollowupAt ?? this.nextFollowupAt),
        reason: reason ?? this.reason,
        nextTry: nextTry ?? this.nextTry,
        stageIsFinal: stageIsFinal ?? this.stageIsFinal,
      );

  /// Null when the form may be saved, else the one thing to fix. The same
  /// wording the server uses for its refusals.
  String? validate() {
    if (connected == null) return 'Say whether the call connected.';
    if (connected == true) {
      if (stageId == null) return 'Choose the stage.';
      if (remark.trim().isEmpty) {
        return 'A remark is required when the call connected.';
      }
      if (!stageIsFinal && nextFollowupAt == null) {
        return 'Set the next follow-up unless the lead is converted or lost.';
      }
      return null;
    }
    if (reason == null || reason!.isEmpty) {
      return 'Choose why the call did not connect.';
    }
    if (nextTry == null || nextTry!.isEmpty) {
      return 'Choose when to try again.';
    }
    if (nextTry == 'pick' && nextFollowupAt == null) {
      return 'Pick the date and time to try again.';
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    if (connected == true) {
      return {
        'connected': true,
        'stage_id': stageId,
        if (tagId != null) 'tag_id': tagId,
        'remark': remark.trim(),
        if (education.trim().isNotEmpty ||
            workExperience.trim().isNotEmpty ||
            coursePackage.trim().isNotEmpty)
          'script': {
            if (education.trim().isNotEmpty) 'education': education.trim(),
            if (workExperience.trim().isNotEmpty)
              'work_experience': workExperience.trim(),
            if (coursePackage.trim().isNotEmpty)
              'course_package': coursePackage.trim(),
          },
        if (nextFollowupAt != null)
          'next_followup_at': _iso(nextFollowupAt!),
      };
    }
    return {
      'connected': false,
      'reason': reason,
      'next_try': nextTry,
      if (nextTry == 'pick' && nextFollowupAt != null)
        'next_followup_at': _iso(nextFollowupAt!),
      if (remark.trim().isNotEmpty) 'remark': remark.trim(),
    };
  }

  @override
  List<Object?> get props => [
        connected,
        stageId,
        tagId,
        remark,
        education,
        workExperience,
        coursePackage,
        nextFollowupAt,
        reason,
        nextTry,
        stageIsFinal,
      ];
}

int? _int(Object? value) => switch (value) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

String _iso(DateTime value) => value.toUtc().toIso8601String();

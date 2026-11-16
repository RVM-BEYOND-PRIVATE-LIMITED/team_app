import 'package:core_network/core_network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/domain/crm_models.dart';
import 'package:rvm_team_app/push/push_service.dart';
import 'package:rvm_team_app/widgets/blocked_state.dart';

/// The CRM's own rules (team_app #51): the setup the server sends, the five
/// buckets, the disposition form's mandatory answers, the masked number, the
/// five notification routes and the CRM refusal codes.
void main() {
  group('the setup', () {
    final setup = CrmSetup.fromJson({
      'pipeline': {'id': 1, 'name': 'Sales'},
      'stages': [
        {
          'id': 1,
          'name': 'OPEN',
          'kind': 'open',
          'position': 1,
          'tags': [
            {'id': 11, 'name': 'diploma lead'}
          ],
        },
        {
          'id': 2,
          'name': 'Not connected',
          'kind': 'not_connected',
          'position': 2,
          'tags': [],
        },
        {
          'id': 3,
          'name': 'IN PROGRESS',
          'kind': 'in_progress',
          'position': 3,
          'tags': [
            {'id': 31, 'name': 'warm'}
          ],
        },
        {
          'id': 4,
          'name': 'CONVERTED',
          'kind': 'converted',
          'position': 4,
          'tags': [],
        },
        {
          'id': 5,
          'name': 'LOST',
          'kind': 'lost',
          'position': 5,
          'tags': [],
        },
      ],
      'moves': [
        {'from_stage_id': 1, 'to_stage_id': 2},
        {'from_stage_id': 1, 'to_stage_id': 3},
        {'from_stage_id': 3, 'to_stage_id': 4},
      ],
      'campaigns': [
        {
          'id': 1,
          'name': 'Enquiries',
          'priority': 2,
          'distribution': 'round_robin',
          'paused': false,
        },
      ],
      'properties': [
        {'key': 'qualification', 'label': 'Qualification', 'type': 'text', 'position': 1},
      ],
      'not_connected_reasons': [
        {
          'code': 'did_not_pick',
          'label': 'Did not pick',
          'retries': 3,
          'gap_minutes': 360,
          'closes_at_once': false,
        },
        {
          'code': 'invalid_number',
          'label': 'Invalid number',
          'retries': 0,
          'gap_minutes': 0,
          'closes_at_once': true,
        },
      ],
      'followup_presets': [
        {'code': '1h', 'minutes': 60},
        {'code': '6h', 'minutes': 360},
        {'code': '1d', 'minutes': 1440},
      ],
      'settings': {
        'web_call_mode': 'push',
        'auto_dial_default': false,
        'form_alert_minutes': 10,
      },
    });

    test('reads the stages, allowed moves, tags and reasons', () {
      expect(setup.pipelineName, 'Sales');
      expect(setup.stages.map((s) => s.name),
          ['OPEN', 'Not connected', 'IN PROGRESS', 'CONVERTED', 'LOST']);
      expect(setup.stage(3)?.tags.single.name, 'warm');
      expect(setup.stage(4)?.kind.isFinal, isTrue);
      expect(setup.reason('invalid_number')?.closesAtOnce, isTrue);
      expect(setup.preset('6h')?.minutes, 360);
    });

    test('offers only the stages the server allows after the current one', () {
      expect(setup.nextStages(1).map((s) => s.id), [1, 2, 3]);
      expect(setup.nextStages(3).map((s) => s.id), [3, 4]);
      // A stage with no move still offers itself, so the stage can be kept.
      expect(setup.nextStages(2).map((s) => s.id), [2]);
    });
  });

  group('the disposition form', () {
    test('connected needs a stage, a remark and a follow-up unless final', () {
      const empty = CrmDispositionDraft();
      expect(empty.validate(), 'Say whether the call connected.');

      const noStage = CrmDispositionDraft(connected: true, remark: 'ok');
      expect(noStage.validate(), 'Choose the stage.');

      const noRemark = CrmDispositionDraft(connected: true, stageId: 3);
      expect(noRemark.validate(),
          'A remark is required when the call connected.');

      const noFollowup = CrmDispositionDraft(
          connected: true, stageId: 3, remark: 'Interested');
      expect(noFollowup.validate(),
          'Set the next follow-up unless the lead is converted or lost.');

      const ok = CrmDispositionDraft(
          connected: true,
          stageId: 3,
          remark: 'Interested',
          nextFollowupAt: null);
      expect(ok.validate(), isNotNull);
    });

    test('a converted or lost stage needs no follow-up', () {
      const converted = CrmDispositionDraft(
        connected: true,
        stageId: 4,
        remark: 'Paid',
        stageIsFinal: true,
      );
      expect(converted.validate(), isNull);
    });

    test('not connected needs a reason and a next try', () {
      const noReason =
          CrmDispositionDraft(connected: false, nextTry: '6h');
      expect(noReason.validate(), 'Choose why the call did not connect.');

      const noTry = CrmDispositionDraft(connected: false, reason: 'busy');
      expect(noTry.validate(), 'Choose when to try again.');

      const pickNoTime = CrmDispositionDraft(
          connected: false, reason: 'busy', nextTry: 'pick');
      expect(pickNoTime.validate(), 'Pick the date and time to try again.');

      const preset = CrmDispositionDraft(
          connected: false, reason: 'busy', nextTry: '6h');
      expect(preset.validate(), isNull);
    });

    test('sends the preset to the server, which works out the time', () {
      const draft = CrmDispositionDraft(
          connected: false, reason: 'did_not_pick', nextTry: '6h');
      final json = draft.toJson();
      expect(json['connected'], isFalse);
      expect(json['reason'], 'did_not_pick');
      expect(json['next_try'], '6h');
      // The server computes 10:00 + 6h on its own clock; the app never sends
      // a time for a preset.
      expect(json.containsKey('next_followup_at'), isFalse);
    });

    test('a picked time travels as an ISO instant', () {
      final at = DateTime(2026, 12, 6, 16, 0);
      final draft = CrmDispositionDraft(
        connected: true,
        stageId: 3,
        remark: 'Wants the weekend batch',
        nextFollowupAt: at,
      );
      final json = draft.toJson();
      expect(json['remark'], 'Wants the weekend batch');
      expect(json['next_followup_at'], at.toUtc().toIso8601String());
    });

    test('a final stage clears the follow-up and the tag', () {
      const warm = CrmDispositionDraft(
          connected: true,
          stageId: 3,
          tagId: 31,
          remark: 'ok',
          nextFollowupAt: null);
      // The bloc's stage event clears the tag; the draft's own rule keeps the
      // form honest even when a caller builds one directly.
      expect(warm.validate(), isNotNull);
      expect(
          warm.copyWith(stageIsFinal: true, clearFollowup: true).validate(),
          isNull);
    });
  });

  group('a lead', () {
    test('keeps only the masked number the server sends', () {
      final lead = CrmLeadSummary.tryParse({
        'id': 501,
        'name': 'Ravi Kumar',
        'phone_masked': '90xxxxxx01',
        'campaign': {'id': 1, 'name': 'Enquiries'},
        'stage': {'id': 3, 'name': 'IN PROGRESS', 'kind': 'in_progress'},
        'tag': {'id': 31, 'name': 'warm'},
        'owner': {'user_id': 'u-1', 'name': 'Counsellor One'},
        'status': 'follow_up',
        'next_followup_at': '2026-12-01T10:00:00+05:30',
        'attempts': 2,
        'last_contact_at': '2026-11-30T10:00:00+05:30',
        'latest_remark': 'Spoke earlier.',
        'source': 'meta',
      })!;
      expect(lead.phoneMasked, '90xxxxxx01');
      expect(lead.stageKind, CrmStageKind.inProgress);
      expect(lead.tagName, 'warm');
      expect(lead.ownerName, 'Counsellor One');
      expect(lead.attempts, 2);
    });

    test('reads a detail with its properties and open call', () {
      final detail = CrmLeadDetail.tryParse({
        'id': 501,
        'name': 'Ravi Kumar',
        'phone_masked': '90xxxxxx01',
        'campaign': {'id': 1, 'name': 'Enquiries'},
        'stage': {'id': 3, 'name': 'IN PROGRESS', 'kind': 'in_progress'},
        'tag': null,
        'owner': null,
        'status': 'in_progress',
        'next_followup_at': null,
        'attempts': 1,
        'last_contact_at': null,
        'latest_remark': null,
        'source': 'meta',
        'alt_phone_masked': null,
        'props': {'qualification': 'Diploma', 'details': 'Weekend batch'},
        'source_detail': {},
        'created_at': '2026-11-28T10:00:00+05:30',
        'assigned_at': null,
        'whatsapp_opt_out': false,
        'referrer_lead_id': null,
        'open_call_id': 9001,
      })!;
      expect(detail.properties['qualification'], 'Diploma');
      expect(detail.openCallId, 9001);
      expect(detail.summary.stageName, 'IN PROGRESS');
    });
  });

  group('the five CRM notification routes', () {
    test('a web Call opens the phone hand-off with both ids', () {
      expect(
          crmRouteFor({'category': 'crm_call', 'call_id': 9001, 'lead_id': 501}),
          '/crm/call/9001?leadId=501');
    });

    test('a callback or a follow-up opens the lead', () {
      expect(crmRouteFor({'category': 'crm_callback', 'lead_id': 501}),
          '/crm/lead/501');
      expect(crmRouteFor({'category': 'crm_followup', 'lead_id': 501}),
          '/crm/lead/501');
    });

    test('a follow-up with no lead opens the calendar', () {
      expect(crmRouteFor({'category': 'crm_followup'}), '/crm/calendar');
    });

    test('leads given to me with no single lead open My Leads', () {
      expect(
          crmRouteFor({'category': 'crm_lead_assigned'}), '/crm/leads');
    });

    test('a Team Leader alert opens the CRM home', () {
      expect(crmRouteFor({'category': 'crm_alert'}), '/crm');
    });

    test('any other category is not a CRM route', () {
      expect(crmRouteFor({'category': 'approvals', 'lead_id': 501}), isNull);
    });
  });

  group('CRM refusals use the shared blocked screen', () {
    Failure forbidden(String code) =>
        Failure.fromStatus(403, 'The server said why.', code);

    test('not punched in', () {
      expect(blockedReasonFor(forbidden('CRM_NOT_PUNCHED_IN')),
          BlockedReason.notPunchedIn);
    });

    test('outside the shift', () {
      expect(blockedReasonFor(forbidden('CRM_OUTSIDE_SHIFT')),
          BlockedReason.outsideShift);
    });

    test('another caller has the lead', () {
      expect(blockedReasonFor(forbidden('CRM_NOT_YOUR_LEAD')),
          BlockedReason.notOwner);
    });

    test('the CRM is not open to this account', () {
      expect(blockedReasonFor(forbidden('CRM_NO_ACCESS')),
          BlockedReason.pilotOnly);
    });

    test('a closed switch is still the one body, shown as module off', () {
      expect(
          blockedReasonFor(const ModuleUnavailableFailure('crm')),
          BlockedReason.moduleOff);
    });

    test('the rate limit keeps the server wording', () {
      expect(blockedReasonFor(const TooManyRequestsFailure()),
          BlockedReason.rateLimited);
    });
  });
}

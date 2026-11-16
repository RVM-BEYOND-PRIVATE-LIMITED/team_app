import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/crm_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import 'bloc/crm_blocs.dart';
import 'crm_shared.dart';
import 'voice_remarks.dart';

/// `/crm/lead/:id/dispose?callId=&origin=` — the mandatory form after a call
/// (team_app #51, items 9–11). It reads the setup and the lead again, so a form
/// lost to an app kill comes back exactly as the server has it.
class CrmDispositionScreen extends StatefulWidget {
  const CrmDispositionScreen({
    super.key,
    required this.leadId,
    required this.callId,
    this.origin = 'dialer',
    this.autoDial = false,
  });

  final int leadId;
  final int callId;
  final String origin;
  final bool autoDial;

  @override
  State<CrmDispositionScreen> createState() => _CrmDispositionScreenState();
}

class _CrmDispositionScreenState extends State<CrmDispositionScreen> {
  bool _loading = true;
  Failure? _failure;
  CrmSetup? _setup;
  CrmLeadDetail? _lead;
  CrmDispositionBloc? _bloc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bloc?.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final results = await Future.wait([
        crmRepository().setup(),
        crmRepository().lead(widget.leadId),
      ]);
      if (!mounted) return;
      final setup = results[0] as CrmSetup;
      final lead = results[1] as CrmLeadDetail;
      final bloc = CrmDispositionBloc(
        repository: crmRepository(),
        setup: setup,
        callId: widget.callId,
        lead: lead,
        remarkIdempotencyKey: IdempotencyInterceptor.newKey(),
      );
      setState(() {
        _setup = setup;
        _lead = lead;
        _bloc = bloc;
        _loading = false;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_loading) {
      return const Scaffold(body: AppLoading(label: 'Opening the form…'));
    }
    if (_failure != null || _setup == null || _lead == null || _bloc == null) {
      return Scaffold(
        backgroundColor: p.canvas,
        appBar: AppBar(title: const Text('Call form')),
        body: crmFailure(_failure, onRetry: _load),
      );
    }
    return BlocProvider.value(
      value: _bloc!,
      child: _CrmDispositionForm(
        setup: _setup!,
        lead: _lead!,
        origin: widget.origin,
        autoDial: widget.autoDial,
      ),
    );
  }
}

class _CrmDispositionForm extends StatefulWidget {
  const _CrmDispositionForm({
    required this.setup,
    required this.lead,
    required this.origin,
    required this.autoDial,
  });

  final CrmSetup setup;
  final CrmLeadDetail lead;
  final String origin;
  final bool autoDial;

  @override
  State<_CrmDispositionForm> createState() => _CrmDispositionFormState();
}

class _CrmDispositionFormState extends State<_CrmDispositionForm> {
  final _remark = TextEditingController();
  final _education = TextEditingController();
  final _experience = TextEditingController();
  final _course = TextEditingController();
  Timer? _ticker;
  Duration _open = Duration.zero;
  bool _handledSaved = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _open += const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _remark.dispose();
    _education.dispose();
    _experience.dispose();
    _course.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BlocConsumer<CrmDispositionBloc, CrmDispositionState>(
      listenWhen: (a, b) => a.saved != b.saved || a.failure != b.failure,
      listener: (context, state) {
        if (state.saved && !_handledSaved) {
          _handledSaved = true;
          _afterSaved(context);
        }
      },
      builder: (context, state) {
        final draft = state.draft;
        final connected = draft.connected;
        final stages = widget.setup.nextStages(widget.lead.summary.stageId);
        final stage = draft.stageId == null
            ? null
            : widget.setup.stage(draft.stageId!);
        final tags = stage?.tags ?? const <CrmTag>[];
        return Scaffold(
          backgroundColor: p.canvas,
          appBar: AppBar(
            title: Text(widget.lead.summary.name),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Text(
                    'Form ${_mmss(_open)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _open > const Duration(minutes: 10)
                              ? p.danger
                              : p.muted,
                        ),
                  ),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(RvmSpacing.md),
            children: [
              TeamCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Did the call connect?',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: RvmSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            selected: connected == true,
                            onSelected: (_) => context
                                .read<CrmDispositionBloc>()
                                .add(const CrmDispositionConnected(true)),
                            label: const Text('Connected'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            selected: connected == false,
                            onSelected: (_) => context
                                .read<CrmDispositionBloc>()
                                .add(const CrmDispositionConnected(false)),
                            label: const Text('Not connected'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (connected == true) ...[
                const SizedBox(height: RvmSpacing.md),
                TeamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: draft.stageId,
                        decoration:
                            const InputDecoration(labelText: 'Stage'),
                        items: [
                          for (final stage in stages)
                            DropdownMenuItem(
                                value: stage.id, child: Text(stage.name)),
                        ],
                        onChanged: (id) {
                          final stage = id == null
                              ? null
                              : widget.setup.stage(id);
                          if (stage != null) {
                            context
                                .read<CrmDispositionBloc>()
                                .add(CrmDispositionStage(stage));
                          }
                        },
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: draft.tagId,
                          decoration: const InputDecoration(labelText: 'Tag'),
                          items: [
                            for (final tag in tags)
                              DropdownMenuItem(
                                  value: tag.id, child: Text(tag.name)),
                          ],
                          onChanged: (id) => context
                              .read<CrmDispositionBloc>()
                              .add(CrmDispositionTag(id)),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _remark,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 2000,
                        onChanged: (value) => context
                            .read<CrmDispositionBloc>()
                            .add(CrmDispositionRemark(value)),
                        decoration: InputDecoration(
                          labelText: 'Remark (required)',
                          suffixIcon: IconButton(
                            tooltip: 'Speak the remark',
                            onPressed: () => _speak(_remark),
                            icon: const Icon(Icons.mic_none),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: const Text('Script answers (optional)'),
                        children: [
                          TextField(
                            controller: _education,
                            maxLength: 300,
                            onChanged: (value) => _script(),
                            decoration:
                                const InputDecoration(labelText: 'Education'),
                          ),
                          TextField(
                            controller: _experience,
                            maxLength: 300,
                            onChanged: (value) => _script(),
                            decoration: const InputDecoration(
                                labelText: 'Work experience'),
                          ),
                          TextField(
                            controller: _course,
                            maxLength: 300,
                            onChanged: (value) => _script(),
                            decoration: const InputDecoration(
                                labelText: 'Course package'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (!(stage?.isFinal ?? false)) ...[
                        OutlinedButton.icon(
                          onPressed: () => _pickFollowup(context, draft),
                          icon: const Icon(Icons.event_outlined),
                          label: Text(draft.nextFollowupAt == null
                              ? 'Set next follow-up (required)'
                              : 'Next follow-up: ${crmWhen(draft.nextFollowupAt!)}'),
                        ),
                        const SizedBox(height: 4),
                      ] else
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                              'A converted or lost lead needs no follow-up.'),
                        ),
                    ],
                  ),
                ),
              ],
              if (connected == false) ...[
                const SizedBox(height: RvmSpacing.md),
                TeamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: draft.reason,
                        decoration:
                            const InputDecoration(labelText: 'Why not?'),
                        items: [
                          for (final reason in widget.setup.reasons)
                            DropdownMenuItem(
                                value: reason.code,
                                child: Text(reason.label)),
                        ],
                        onChanged: (code) {
                          if (code != null) {
                            context
                                .read<CrmDispositionBloc>()
                                .add(CrmDispositionReason(code));
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Text('Try again',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final preset in widget.setup.followupPresets)
                            ChoiceChip(
                              selected: draft.nextTry == preset.code,
                              onSelected: (_) => context
                                  .read<CrmDispositionBloc>()
                                  .add(CrmDispositionNextTry(preset.code)),
                              label: Text(preset.label),
                            ),
                          ChoiceChip(
                            selected: draft.nextTry == 'pick',
                            onSelected: (_) => context
                                .read<CrmDispositionBloc>()
                                .add(const CrmDispositionNextTry('pick')),
                            label: const Text('Pick a time'),
                          ),
                        ],
                      ),
                      if (draft.nextTry == 'pick') ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _pickFollowup(context, draft),
                          icon: const Icon(Icons.event_outlined),
                          label: Text(draft.nextFollowupAt == null
                              ? 'Pick date and time'
                              : crmWhen(draft.nextFollowupAt!)),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _remark,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 2000,
                        onChanged: (value) => context
                            .read<CrmDispositionBloc>()
                            .add(CrmDispositionRemark(value)),
                        decoration: InputDecoration(
                          labelText: 'Remark',
                          suffixIcon: IconButton(
                            tooltip: 'Speak the remark',
                            onPressed: () => _speak(_remark),
                            icon: const Icon(Icons.mic_none),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (state.failure != null) ...[
                const SizedBox(height: RvmSpacing.md),
                Text(
                  state.failure!.message,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: p.danger),
                ),
              ],
              const SizedBox(height: RvmSpacing.lg),
              FilledButton.icon(
                onPressed: connected == null || state.submitting
                    ? null
                    : () => context
                        .read<CrmDispositionBloc>()
                        .add(const CrmDispositionSubmit()),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                icon: state.submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(state.submitting ? 'Saving…' : 'Save and finish'),
              ),
              const SizedBox(height: RvmSpacing.lg),
            ],
          ),
        );
      },
    );
  }

  void _script() {
    context.read<CrmDispositionBloc>().add(CrmDispositionScript(
          education: _education.text,
          workExperience: _experience.text,
          coursePackage: _course.text,
        ));
  }

  Future<void> _speak(TextEditingController controller) async {
    final text = await VoiceRemarks.listen();
    if (text == null || !mounted) return;
    final current = controller.text.trim();
    controller.text = current.isEmpty ? text : '$current $text';
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    context
        .read<CrmDispositionBloc>()
        .add(CrmDispositionRemark(controller.text));
  }

  Future<void> _pickFollowup(
      BuildContext context, CrmDispositionDraft draft) async {
    final initial = draft.nextFollowupAt ??
        DateTime.now().add(const Duration(hours: 1));
    final at = await pickCrmDateTime(context, initial);
    if (at != null && context.mounted) {
      context.read<CrmDispositionBloc>().add(CrmDispositionFollowup(at));
    }
  }

  Future<void> _afterSaved(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    if (!widget.autoDial) {
      router.go('/crm');
      return;
    }
    try {
      final next = await crmRepository().next();
      if (!context.mounted) return;
      if (next.lead == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Saved. No lead is waiting for you.')));
        router.go('/crm');
        return;
      }
      await startCrmCall(context, leadId: next.lead!.id);
    } on Failure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      router.go('/crm');
    }
  }

  static String _mmss(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:'
      '${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}

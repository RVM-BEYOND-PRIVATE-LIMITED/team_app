import 'dart:async';

import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import 'bloc/wfh_allowances_bloc.dart';

/// HR's work-from-home allowances (KP, 22 Oct): enable WFH per employee and set
/// that person's monthly days. `GET/PUT /hr/wfh-allowances` — hr, CEO and super
/// admin only. An HR Executive gets the server's 403, so the tile is gated.
class HrWfhAllowancesScreen extends StatelessWidget {
  const HrWfhAllowancesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<WfhAllowancesBloc>()..add(const WfhAllowancesLoadRequested()),
      child: const _WfhAllowancesView(),
    );
  }
}

class _WfhAllowancesView extends StatefulWidget {
  const _WfhAllowancesView();

  @override
  State<_WfhAllowancesView> createState() => _WfhAllowancesViewState();
}

class _WfhAllowancesViewState extends State<_WfhAllowancesView> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        context
            .read<WfhAllowancesBloc>()
            .add(WfhAllowancesSearchChanged(value.trim()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WfhAllowancesBloc, WfhAllowancesState>(
      listenWhen: (a, b) =>
          a.actionFailure != b.actionFailure || a.savedNonce != b.savedNonce,
      listener: (context, state) {
        final failure = state.actionFailure;
        final message = failure != null
            ? failure.message
            : (state.savedNonce > 0 ? 'Allowance saved.' : null);
        if (message == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      },
      builder: (context, state) => TeamScaffold(
        title: 'WFH allowances',
        actions: [
          IconButton(
            tooltip: 'Add an employee',
            onPressed: state.submitting ? null : () => _addEmployee(context),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: 'Search by name or employee code',
                  hintStyle: const TextStyle(fontSize: 13),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
            Expanded(child: _body(context, state)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WfhAllowancesState state) {
    final page = state.page;
    if (state.status == LoadStatus.initial ||
        (state.status == LoadStatus.loading && page == null)) {
      return const AppLoading();
    }
    if (state.status == LoadStatus.failure && page == null) {
      return AppError(
        message: state.failure?.message ?? 'Could not load the allowances.',
        onRetry: () => context
            .read<WfhAllowancesBloc>()
            .add(WfhAllowancesLoadRequested(state.query)),
      );
    }
    final rows = page?.rows ?? const <HrWfhAllowance>[];
    if (rows.isEmpty) {
      return AppEmpty(
        icon: Icons.home_work_outlined,
        message: state.query.isEmpty
            ? 'No employee has work from home yet. Add one with the icon above.'
            : 'No employee matches this search.',
      );
    }
    return RefreshIndicator(
      onRefresh: () async => context
          .read<WfhAllowancesBloc>()
          .add(WfhAllowancesLoadRequested(state.query)),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: rows.length + (page?.truncated == true ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i >= rows.length) {
            return const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Showing the first 200. Search to narrow the list.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return _AllowanceCard(
            allowance: rows[i],
            busy: state.submitting,
            onChanged: (enabled) => _save(rows[i], enabled: enabled),
            onEdit: () => _edit(context, rows[i]),
          );
        },
      ),
    );
  }

  void _save(HrWfhAllowance allowance,
      {required bool enabled, int? days, String? note}) {
    context.read<WfhAllowancesBloc>().add(WfhAllowancesSaved(
          employeeId: allowance.employeeId,
          enabled: enabled,
          monthlyLimitDays: days ?? allowance.monthlyLimitDays,
          note: note ?? allowance.note,
        ));
  }

  Future<void> _edit(BuildContext context, HrWfhAllowance allowance) async {
    final result = await showWfhAllowanceEditor(
      context,
      name: allowance.employee.fullName,
      enabled: allowance.enabled,
      days: allowance.monthlyLimitDays,
      note: allowance.note ?? '',
    );
    if (result == null || !context.mounted) return;
    _save(allowance,
        enabled: result.enabled, days: result.days, note: result.note);
  }

  Future<void> _addEmployee(BuildContext context) async {
    final picked = await showModalBottomSheet<OrgCard>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _EmployeePicker(),
    );
    if (picked == null || !context.mounted) return;
    final result = await showWfhAllowanceEditor(
      context,
      name: picked.fullName,
      enabled: true,
      days: 4,
      note: '',
    );
    if (result == null || !context.mounted) return;
    context.read<WfhAllowancesBloc>().add(WfhAllowancesSaved(
          employeeId: picked.id,
          enabled: result.enabled,
          monthlyLimitDays: result.days,
          note: result.note,
        ));
  }
}

class _AllowanceCard extends StatelessWidget {
  const _AllowanceCard({
    required this.allowance,
    required this.busy,
    required this.onChanged,
    required this.onEdit,
  });
  final HrWfhAllowance allowance;
  final bool busy;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = allowance.employee;
    final where = [
      if (e.employeeCode != null) e.employeeCode!,
      if (e.branch != null) e.branch!.name,
      if (e.department != null) e.department!.name,
    ].join(' · ');
    return TeamCard(
      padding: EdgeInsets.zero,
      onTap: busy ? null : onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            TeamAvatar(name: e.fullName, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(fontSize: 13)),
                  if (where.isNotEmpty)
                    Text(where,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                            fontSize: 10, color: RvmColors.muted)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      TeamPill(
                        label: allowance.enabled ? 'WFH on' : 'WFH off',
                        tone: allowance.enabled
                            ? TeamPillTone.success
                            : TeamPillTone.neutral,
                        dense: true,
                      ),
                      const SizedBox(width: 6),
                      Text('${allowance.monthlyLimitDays} day'
                          '${allowance.monthlyLimitDays == 1 ? '' : 's'}/month',
                          style: text.bodySmall?.copyWith(
                              fontSize: 10, color: RvmColors.muted)),
                    ],
                  ),
                  if (allowance.note != null &&
                      allowance.note!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(allowance.note!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                              fontSize: 10, color: RvmColors.subtle)),
                    ),
                ],
              ),
            ),
            Switch(
              value: allowance.enabled,
              onChanged: busy ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// The enable/disable + monthly-days editor. Returns null on cancel.
Future<({bool enabled, int days, String? note})?> showWfhAllowanceEditor(
  BuildContext context, {
  required String name,
  required bool enabled,
  required int days,
  required String note,
}) {
  return showModalBottomSheet<({bool enabled, int days, String? note})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AllowanceEditor(
        name: name, enabled: enabled, days: days, note: note),
  );
}

class _AllowanceEditor extends StatefulWidget {
  const _AllowanceEditor({
    required this.name,
    required this.enabled,
    required this.days,
    required this.note,
  });
  final String name;
  final bool enabled;
  final int days;
  final String note;

  @override
  State<_AllowanceEditor> createState() => _AllowanceEditorState();
}

class _AllowanceEditorState extends State<_AllowanceEditor> {
  late bool _enabled = widget.enabled;
  late int _days = widget.days.clamp(1, 31);
  late final _note = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Work from home · ${widget.name}',
              style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'The person can file up to this many days a month. Turning it off '
            'keeps the limit for the next switch-on.',
            style: text.bodySmall?.copyWith(color: RvmColors.muted),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Work from home enabled'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          Row(
            children: [
              Expanded(
                child: Text('Days a month', style: text.bodyMedium),
              ),
              IconButton(
                tooltip: 'One day fewer',
                onPressed: _days <= 1 ? null : () => setState(() => _days--),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 36,
                child: Text('$_days',
                    textAlign: TextAlign.center,
                    style: text.titleMedium),
              ),
              IconButton(
                tooltip: 'One day more',
                onPressed: _days >= 31 ? null : () => setState(() => _days++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Note for HR (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              enabled: _enabled,
              days: _days,
              note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            )),
            child: const Text('Save allowance'),
          ),
        ],
      ),
    );
  }
}

/// Search the ESS directory for an employee to enable WFH for.
class _EmployeePicker extends StatefulWidget {
  const _EmployeePicker();

  @override
  State<_EmployeePicker> createState() => _EmployeePickerState();
}

class _EmployeePickerState extends State<_EmployeePicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<OrgCard> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(value));
  }

  Future<void> _run(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await getIt<EssRepository>().directory(query: q);
      if (!mounted) return;
      setState(() {
        _results = page.people;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not search. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enable work from home',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onSearch,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search by name or employee code',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(child: Center(child: Text(_error!)))
            else if (_results.isEmpty)
              const Expanded(
                  child: Center(
                      child: Text('Type a name to find a colleague.')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final p = _results[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: TeamAvatar(name: p.fullName, size: 36),
                      title: Text(p.fullName),
                      subtitle: Text([
                        if (p.employeeCode != null) p.employeeCode!,
                        if (p.designation != null) p.designation!,
                        if (p.branch != null) p.branch!.name,
                      ].join(' · ')),
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

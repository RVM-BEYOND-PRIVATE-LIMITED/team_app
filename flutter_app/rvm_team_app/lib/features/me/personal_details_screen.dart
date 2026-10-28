import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app_validators.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import 'bloc/personal_bloc.dart';

/// E9: date of birth, blood group, address and emergency contact. HR owns the
/// sensitive fields; the employee may change only their blood group and
/// emergency contact (the rest is read-only here).
class PersonalDetailsScreen extends StatelessWidget {
  const PersonalDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<PersonalBloc>()..add(const PersonalLoadRequested()),
      child: const _PersonalView(),
    );
  }
}

class _PersonalView extends StatefulWidget {
  const _PersonalView();

  @override
  State<_PersonalView> createState() => _PersonalViewState();
}

class _PersonalViewState extends State<_PersonalView> {
  static const _bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-'
  ];

  final _emergencyName = TextEditingController();
  final _emergencyRelation = TextEditingController();
  final _emergencyPhone = TextEditingController();
  String? _bloodGroup;
  String? _phoneError;
  bool _seeded = false;
  bool _workSeeded = false;
  List<WorkExperience> _workExperience = [];

  @override
  void dispose() {
    _emergencyName.dispose();
    _emergencyRelation.dispose();
    _emergencyPhone.dispose();
    super.dispose();
  }

  void _seed(PersonalDetails? p) {
    if (_seeded || p == null) return;
    _seeded = true;
    _bloodGroup = p.bloodGroup;
    _emergencyName.text = p.emergencyName ?? '';
    _emergencyRelation.text = p.emergencyRelation ?? '';
    _emergencyPhone.text = p.emergencyPhone ?? '';
  }

  void _seedWork(List<WorkExperience> entries) {
    if (_workSeeded) return;
    _workSeeded = true;
    _workExperience = List<WorkExperience>.from(entries);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal details'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () =>
                context.read<PersonalBloc>().add(const PersonalRefreshed()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocConsumer<PersonalBloc, PersonalState>(
        listenWhen: (a, b) =>
            a.savedNonce != b.savedNonce || a.saveFailure != b.saveFailure,
        listener: (context, state) {
          if (state.savedNonce > 0 && state.saveFailure == null) {
            final messenger = ScaffoldMessenger.of(context);
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                  const SnackBar(content: Text('Personal details saved.')));
            // The save is complete, so this form has nothing left to do. Going
            // back is the confirmation the person expects; the SnackBar lives on
            // the app's root messenger and stays visible over the previous page.
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          } else if (state.saveFailure != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                  SnackBar(content: Text(state.saveFailure!.message)));
          }
        },
        builder: (context, state) {
          if (state.status == LoadStatus.initial ||
              (state.status == LoadStatus.loading && state.data == null)) {
            return const AppLoading();
          }
          switch (state.status) {
            case LoadStatus.failure:
              return AppError(
                message: state.failure?.message ??
                    'Could not load your personal details.',
                onRetry: () =>
                    context.read<PersonalBloc>().add(const PersonalRefreshed()),
              );
            case LoadStatus.initial:
            case LoadStatus.loading:
            case LoadStatus.empty:
            case LoadStatus.success:
              _seed(state.data);
              _seedWork(state.workExperience);
              return _form(context, state);
          }
        },
      ),
    );
  }

  Widget _form(BuildContext context, PersonalState state) {
    final p = state.data;
    return ListView(
      padding: const EdgeInsets.all(RvmSpacing.md),
      children: [
        Text('HR record', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: RvmSpacing.sm),
        Card(
          child: Column(
            children: [
              _ReadOnly(
                  icon: Icons.cake_outlined,
                  label: 'Date of birth',
                  value: p?.dateOfBirth),
              const Divider(height: 1),
              _ReadOnly(
                  icon: Icons.home_outlined,
                  label: 'Address',
                  value: p?.addressOneLine),
            ],
          ),
        ),
        const SizedBox(height: RvmSpacing.md),
        Text('You can change', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: RvmSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(RvmSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _bloodGroup,
                  decoration: const InputDecoration(
                      labelText: 'Blood group', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Not set')),
                    for (final g in _bloodGroups)
                      DropdownMenuItem(value: g, child: Text(g)),
                  ],
                  onChanged: (v) => setState(() => _bloodGroup = v),
                ),
                const SizedBox(height: RvmSpacing.md),
                TextField(
                  controller: _emergencyName,
                  maxLength: 100,
                  decoration: const InputDecoration(
                      labelText: 'Emergency contact name', counterText: ''),
                ),
                const SizedBox(height: RvmSpacing.sm),
                TextField(
                  controller: _emergencyRelation,
                  maxLength: 50,
                  decoration: const InputDecoration(
                      labelText: 'Relationship', counterText: ''),
                ),
                const SizedBox(height: RvmSpacing.sm),
                TextField(
                  controller: _emergencyPhone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: (_) {
                    if (_phoneError != null) {
                      setState(() => _phoneError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Emergency phone',
                    hintText: '10-digit mobile number',
                    counterText: '',
                    errorText: _phoneError,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (state.workExperienceAvailable) ...[
          const SizedBox(height: RvmSpacing.md),
          Text('Work experience',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: RvmSpacing.sm),
          _WorkExperienceSection(
            entries: _workExperience,
            onAdd: () => _editWork(context, null),
            onEdit: (e) => _editWork(context, e),
            onDelete: (e) => setState(
                () => _workExperience.removeWhere((entry) => entry.id == e.id)),
          ),
        ],
        if (p?.updatedByName != null || p?.updatedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: RvmSpacing.sm),
            child: Text(
              [
                if (p?.updatedByName != null)
                  'Last updated by ${p!.updatedByName}',
                if (p?.updatedAt != null)
                  'on ${MaterialLocalizations.of(context).formatMediumDate(p!.updatedAt!.toLocal())}',
              ].join(' '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: RvmSpacing.lg),
        FilledButton.icon(
          onPressed: state.saving ? null : () => _save(context),
          icon: state.saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: const Text('Save changes'),
        ),
        const SizedBox(height: RvmSpacing.lg),
      ],
    );
  }

  void _save(BuildContext context) {
    final phone = _emergencyPhone.text.trim();
    if (phone.isNotEmpty && !isValidPhone10(phone)) {
      setState(() => _phoneError = 'Enter a valid 10-digit mobile number.');
      return;
    }
    setState(() => _phoneError = null);
    context.read<PersonalBloc>().add(PersonalSubmitted(
          bloodGroup: _bloodGroup,
          emergencyName: _emergencyName.text.trim(),
          emergencyRelation: _emergencyRelation.text.trim(),
          emergencyPhone: phone,
          workExperience: _workExperience,
        ));
  }

  Future<void> _editWork(BuildContext context, WorkExperience? current) async {
    final saved = await showModalBottomSheet<WorkExperience>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _WorkExperienceSheet(initial: current),
    );
    if (saved == null || !mounted) return;
    setState(() {
      final index = _workExperience
          .indexWhere((entry) => current != null && entry.id == current.id);
      if (index >= 0) {
        _workExperience[index] = saved;
      } else {
        _workExperience.add(saved);
      }
    });
  }
}

class _ReadOnly extends StatelessWidget {
  const _ReadOnly(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(label),
      subtitle:
          Text((value == null || value!.isEmpty) ? 'Not recorded' : value!),
      trailing:
          Icon(Icons.lock_outline, size: 18, color: scheme.onSurfaceVariant),
      enabled: false,
    );
  }
}

class _WorkExperienceSection extends StatelessWidget {
  const _WorkExperienceSection({
    required this.entries,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<WorkExperience> entries;
  final VoidCallback onAdd;
  final ValueChanged<WorkExperience> onEdit;
  final ValueChanged<WorkExperience> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(RvmSpacing.md),
              child: Column(
                children: [
                  Text('No work experience added yet.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: RvmSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add work experience'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          for (final entry in entries) ...[
            _WorkExperienceCard(
                entry: entry,
                onEdit: () => onEdit(entry),
                onDelete: () => onDelete(entry)),
            const SizedBox(height: RvmSpacing.sm),
          ],
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add another role'),
          ),
        ],
      ],
    );
  }
}

class _WorkExperienceCard extends StatelessWidget {
  const _WorkExperienceCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final WorkExperience entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dates = entry.isCurrent
        ? '${_monthYear(entry.fromDate)} – Present'
        : entry.toDate == null
            ? _monthYear(entry.fromDate)
            : '${_monthYear(entry.fromDate)} – ${_monthYear(entry.toDate!)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            RvmSpacing.md, RvmSpacing.sm, RvmSpacing.sm, RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.company,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(entry.roleTitle,
                          style: Theme.of(context).textTheme.bodyMedium),
                      Text(dates, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: RvmColors.danger),
                ),
              ],
            ),
            if (entry.location != null && entry.location!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 13, color: RvmColors.subtle),
                  const SizedBox(width: 3),
                  Text(entry.location!,
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ],
            if (entry.description != null && entry.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(entry.description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (entry.isCurrent)
                  const _WorkPill(label: 'Current', tone: _WorkTone.success),
                _WorkPill(
                  label: entry.isVisible ? 'Visible to team' : 'Hidden',
                  tone: entry.isVisible ? _WorkTone.info : _WorkTone.neutral,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _WorkTone { neutral, info, success }

class _WorkPill extends StatelessWidget {
  const _WorkPill({required this.label, required this.tone});
  final String label;
  final _WorkTone tone;

  @override
  Widget build(BuildContext context) {
    final (color, background) = switch (tone) {
      _WorkTone.info => (RvmColors.info, RvmColors.infoSoft),
      _WorkTone.success => (RvmColors.success, RvmColors.successSoft),
      _WorkTone.neutral => (RvmColors.muted, RvmColors.cream),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

String _monthYear(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[date.month - 1]} ${date.year}';
}

String _isoDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class _WorkExperienceSheet extends StatefulWidget {
  const _WorkExperienceSheet({this.initial});
  final WorkExperience? initial;

  @override
  State<_WorkExperienceSheet> createState() => _WorkExperienceSheetState();
}

class _WorkExperienceSheetState extends State<_WorkExperienceSheet> {
  final _company = TextEditingController();
  final _role = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  bool _current = false;
  bool _visible = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.initial;
    if (entry != null) {
      _company.text = entry.company;
      _role.text = entry.roleTitle;
      _location.text = entry.location ?? '';
      _description.text = entry.description ?? '';
      _from = DateTime.tryParse(entry.fromDate);
      _to = entry.toDate == null ? null : DateTime.tryParse(entry.toDate!);
      _current = entry.isCurrent;
      _visible = entry.isVisible;
    }
  }

  @override
  void dispose() {
    _company.dispose();
    _role.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: DateTime(1950),
      lastDate: now,
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? now,
      firstDate: _from ?? DateTime(1950),
      lastDate: now,
    );
    if (picked != null) setState(() => _to = picked);
  }

  void _save() {
    final company = _company.text.trim();
    final role = _role.text.trim();
    if (company.isEmpty) {
      setState(() => _error = 'Company is required.');
      return;
    }
    if (role.isEmpty) {
      setState(() => _error = 'Job title is required.');
      return;
    }
    if (_from == null) {
      setState(() => _error = 'Start date is required.');
      return;
    }
    if (!_current && _to != null && _to!.isBefore(_from!)) {
      setState(() => _error = 'End date cannot be before the start date.');
      return;
    }
    final entry = WorkExperience(
      id: widget.initial?.id ??
          'local-${DateTime.now().microsecondsSinceEpoch.toString()}',
      company: company,
      roleTitle: role,
      fromDate: _isoDay(_from!),
      toDate: _current ? null : (_to == null ? null : _isoDay(_to!)),
      isCurrent: _current,
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      isVisible: _visible,
    );
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                widget.initial == null
                    ? 'Add work experience'
                    : 'Edit work experience',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: RvmSpacing.md),
            TextField(
              controller: _company,
              maxLength: 200,
              decoration:
                  const InputDecoration(labelText: 'Company', counterText: ''),
            ),
            const SizedBox(height: RvmSpacing.sm),
            TextField(
              controller: _role,
              maxLength: 200,
              decoration: const InputDecoration(
                  labelText: 'Job title', counterText: ''),
            ),
            const SizedBox(height: RvmSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFrom,
                    icon: const Icon(Icons.calendar_month_outlined, size: 17),
                    label: Text(_from == null ? 'Start date' : _isoDay(_from!)),
                  ),
                ),
                const SizedBox(width: RvmSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _current ? null : _pickTo,
                    icon: const Icon(Icons.event_outlined, size: 17),
                    label: Text(_to == null ? 'End date' : _isoDay(_to!)),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _current,
              onChanged: (v) => setState(() {
                _current = v;
                if (v) _to = null;
              }),
              title: const Text('I currently work here'),
            ),
            TextField(
              controller: _location,
              maxLength: 200,
              decoration: const InputDecoration(
                  labelText: 'Location (optional)', counterText: ''),
            ),
            const SizedBox(height: RvmSpacing.sm),
            TextField(
              controller: _description,
              maxLength: 1000,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'Description (optional)', counterText: ''),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _visible,
              onChanged: (v) => setState(() => _visible = v),
              title: const Text('Show on my profile'),
              subtitle:
                  const Text('Colleagues can see this role on your profile.'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!,
                    style: const TextStyle(color: RvmColors.danger)),
              ),
            const SizedBox(height: RvmSpacing.md),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save work experience'),
            ),
          ],
        ),
      ),
    );
  }
}

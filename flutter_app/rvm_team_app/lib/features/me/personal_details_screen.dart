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
        ));
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

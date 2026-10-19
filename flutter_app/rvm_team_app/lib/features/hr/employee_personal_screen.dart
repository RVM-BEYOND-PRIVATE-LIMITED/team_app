import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import 'bloc/employee_personal_bloc.dart';

/// E9 (HR side): HR enters or corrects any of an employee's personal details.
/// Reached from an HR Tools row; the call is role-gated by the backend.
class EmployeePersonalScreen extends StatelessWidget {
  const EmployeePersonalScreen({super.key, required this.employeeId, this.employeeName});
  final String employeeId;
  final String? employeeName;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<EmployeePersonalBloc>(param1: employeeId)
        ..add(const EmployeePersonalLoadRequested()),
      child: _EmployeePersonalView(employeeName: employeeName),
    );
  }
}

class _EmployeePersonalView extends StatefulWidget {
  const _EmployeePersonalView({this.employeeName});
  final String? employeeName;

  @override
  State<_EmployeePersonalView> createState() => _EmployeePersonalViewState();
}

class _EmployeePersonalViewState extends State<_EmployeePersonalView> {
  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  final _fields = <String, TextEditingController>{
    'date_of_birth': TextEditingController(),
    'address_line1': TextEditingController(),
    'address_line2': TextEditingController(),
    'city': TextEditingController(),
    'state': TextEditingController(),
    'pincode': TextEditingController(),
    'emergency_name': TextEditingController(),
    'emergency_relation': TextEditingController(),
    'emergency_phone': TextEditingController(),
  };
  String? _bloodGroup;
  bool _seeded = false;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(PersonalDetails? p) {
    if (_seeded || p == null) return;
    _seeded = true;
    _bloodGroup = p.bloodGroup;
    _fields['date_of_birth']!.text = p.dateOfBirth ?? '';
    _fields['address_line1']!.text = p.addressLine1 ?? '';
    _fields['address_line2']!.text = p.addressLine2 ?? '';
    _fields['city']!.text = p.city ?? '';
    _fields['state']!.text = p.state ?? '';
    _fields['pincode']!.text = p.pincode ?? '';
    _fields['emergency_name']!.text = p.emergencyName ?? '';
    _fields['emergency_relation']!.text = p.emergencyRelation ?? '';
    _fields['emergency_phone']!.text = p.emergencyPhone ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.employeeName ?? 'Personal details')),
      body: BlocConsumer<EmployeePersonalBloc, EmployeePersonalState>(
        listenWhen: (a, b) => a.savedNonce != b.savedNonce || a.message != b.message,
        listener: (context, state) {
          if (state.message != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.message!)));
          } else if (state.savedNonce > 0) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Saved.')));
          }
        },
        builder: (context, state) {
          switch (state.status) {
            case LoadStatus.initial:
            case LoadStatus.loading:
              return const AppLoading();
            case LoadStatus.failure:
              return AppError(
                message: state.failure?.message ?? 'Could not load this record.',
                onRetry: () => context.read<EmployeePersonalBloc>().add(const EmployeePersonalLoadRequested()),
              );
            case LoadStatus.empty:
            case LoadStatus.success:
              _seed(state.personal);
              return _form(context, state);
          }
        },
      ),
    );
  }
  Widget _form(BuildContext context, EmployeePersonalState state) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(RvmSpacing.md),
      children: [
        if (state.employee != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(state.employee!.fullName),
              subtitle: Text(state.employee!.employeeCode ?? ''),
            ),
          ),
        const SizedBox(height: RvmSpacing.md),
        _field(context, 'date_of_birth', 'Date of birth (YYYY-MM-DD)', keyboard: TextInputType.datetime),
        DropdownButtonFormField<String>(
          initialValue: _bloodGroup,
          decoration: const InputDecoration(labelText: 'Blood group', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: null, child: Text('Not set')),
            for (final g in _bloodGroups) DropdownMenuItem(value: g, child: Text(g)),
          ],
          onChanged: (v) => setState(() => _bloodGroup = v),
        ),
        const SizedBox(height: RvmSpacing.sm),
        _field(context, 'address_line1', 'Address line 1'),
        const SizedBox(height: RvmSpacing.sm),
        _field(context, 'address_line2', 'Address line 2'),
        const SizedBox(height: RvmSpacing.sm),
        _field(context, 'city', 'City'),
        const SizedBox(height: RvmSpacing.sm),
        _field(context, 'state', 'State'),
        const SizedBox(height: RvmSpacing.sm),
        _field(context, 'pincode', 'Pincode', keyboard: TextInputType.number),
        const SizedBox(height: RvmSpacing.md),
        Text('Emergency contact', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: RvmSpacing.sm),
        _field(context, 'emergency_name', 'Contact name'),
        const SizedBox(height: RvmSpacing.sm),
        _field(context, 'emergency_relation', 'Relationship'),
        const SizedBox(height: RvmSpacing.sm),
        _field(context, 'emergency_phone', 'Phone', keyboard: TextInputType.phone),
        const SizedBox(height: RvmSpacing.lg),
        FilledButton.icon(
          onPressed: state.saving ? null : () => _save(context),
          icon: state.saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
        const SizedBox(height: RvmSpacing.sm),
        Text(
          'HR sets every field. Only blood group and emergency contact are employee-editable.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: RvmSpacing.lg),
      ],
    );
  }

  Widget _field(BuildContext context, String key, String label, {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RvmSpacing.sm),
      child: TextField(
        controller: _fields[key],
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  void _save(BuildContext context) {
    String? v(String key) {
      final t = _fields[key]!.text.trim();
      return t.isEmpty ? null : t;
    }

    context.read<EmployeePersonalBloc>().add(EmployeePersonalSubmitted({
      'date_of_birth': v('date_of_birth'),
      'blood_group': _bloodGroup,
      'address_line1': v('address_line1'),
      'address_line2': v('address_line2'),
      'city': v('city'),
      'state': v('state'),
      'pincode': v('pincode'),
      'emergency_name': v('emergency_name'),
      'emergency_relation': v('emergency_relation'),
      'emergency_phone': v('emergency_phone'),
    }));
  }
}

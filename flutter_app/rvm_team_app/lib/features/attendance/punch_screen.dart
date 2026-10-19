import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/attendance_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import 'bloc/punch_bloc.dart';

/// The geofenced self punch (Scheduler path): today, the month, this phone and
/// the rules. Punch-in is Forge Orange, punch-out Ironwood (decision 16).
class PunchScreen extends StatelessWidget {
  const PunchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<PunchBloc>()..add(const PunchLoadRequested()),
      child: const _PunchView(),
    );
  }
}

class _PunchView extends StatelessWidget {
  const _PunchView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Punch'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => context.read<PunchBloc>().add(const PunchRefreshed()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocConsumer<PunchBloc, PunchState>(
        listenWhen: (a, b) => a.message != b.message || a.remarksNonce != b.remarksNonce,
        listener: (context, state) {
          if (state.message != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.message!)));
          }
        },
        builder: (context, state) {
          switch (state.status) {
            case LoadStatus.initial:
            case LoadStatus.loading:
              return const AppLoading(label: 'Getting your location...');
            case LoadStatus.failure:
              return AppError(
                message: state.failure?.message ?? 'Could not load attendance.',
                onRetry: () => context.read<PunchBloc>().add(const PunchRefreshed()),
              );
            case LoadStatus.empty:
            case LoadStatus.success:
              final data = state.data;
              if (data == null) return const AppEmpty(message: 'Nothing to show.');
              if (!data.linked) {
                return AppEmpty(message: data.message ?? 'Your login is not linked to an employee record yet.');
              }
              if (data.mustSetPassword) {
                return _SetPasswordCard(name: data.employeeName);
              }
              return _body(context, state, data);
          }
        },
      ),
    );
  }
  Widget _body(BuildContext context, PunchState state, MyAttendance data) {
    final today = data.today;
    final device = data.device;
    final canPunch = device == null || device.thisPhone == 'own' || device.canRegister;
    final isIn = today?.punchedIn ?? false;
    final done = today?.done ?? false;

    return ListView(
      padding: const EdgeInsets.all(RvmSpacing.md),
      children: [
        _StatusCard(today: today, shift: data.shift, branch: data.branch),
        const SizedBox(height: RvmSpacing.md),
        if (!canPunch) _DeviceWarning(device: device),
        FilledButton(
          onPressed: (state.punching || done || !canPunch) ? null : () => _punch(context, isIn ? 'out' : 'in'),
          style: FilledButton.styleFrom(
            backgroundColor: isIn ? RvmColors.ironwood : RvmColors.teamSeed,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
          ),
          child: state.punching
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(
                  done ? 'Punched out for today' : (isIn ? 'Punch out' : 'Punch in'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: RvmSpacing.sm),
        Center(
          child: TextButton.icon(
            onPressed: today == null ? null : () => _remark(context, today),
            icon: const Icon(Icons.edit_note),
            label: const Text('Add a remark for today'),
          ),
        ),
        if (today != null && today.punches.isNotEmpty) ...[
          const SizedBox(height: RvmSpacing.md),
          Text('Today', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: RvmSpacing.sm),
          Card(
            child: Column(
              children: [
                for (final p in today.punches)
                  ListTile(
                    dense: true,
                    leading: Icon(p.kind == 'in' ? Icons.login : Icons.logout),
                    title: Text(p.kind == 'in' ? 'Punched in' : 'Punched out'),
                    trailing: Text(p.at == null
                        ? ''
                        : TimeOfDay.fromDateTime(p.at!.toLocal()).format(context)),
                  ),
              ],
            ),
          ),
        ],
        if (data.days.isNotEmpty) ...[
          const SizedBox(height: RvmSpacing.lg),
          Text('This month', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: RvmSpacing.sm),
          Card(
            child: Column(
              children: [for (final d in data.days.reversed.take(15)) _DayRow(day: d)],
            ),
          ),
        ],
      ],
    );
  }

  void _punch(BuildContext context, String kind) {
    context.read<PunchBloc>().add(PunchRequested(kind));
  }

  Future<void> _remark(BuildContext context, PunchToday today) async {
    final existing = context.read<PunchBloc>().state.data?.myRemarks ?? const <AttendanceRemark>[];
    final mine = existing.where((r) => r.day == today.day);
    final controller = TextEditingController(text: mine.isEmpty ? '' : mine.first.remarks);
    final bloc = context.read<PunchBloc>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remark for today'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'The bus was late...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) bloc.add(PunchRemarkRequested(controller.text.trim()));
  }
}

/// First-time / no password: the session cannot punch until the person chooses
/// their own password (POST /hr/my-attendance/password).
class _SetPasswordCard extends StatefulWidget {
  const _SetPasswordCard({this.name});
  final String? name;

  @override
  State<_SetPasswordCard> createState() => _SetPasswordCardState();
}

class _SetPasswordCardState extends State<_SetPasswordCard> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = context.select<PunchBloc, bool>((b) => b.state.punching);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(RvmSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_reset, size: 44, color: scheme.primary),
                const SizedBox(height: RvmSpacing.md),
                Text('Choose your attendance password',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: RvmSpacing.xs),
                Text(
                  widget.name == null
                      ? 'You signed in with the password HR gave. Set your own before you can punch.'
                      : 'Hi ${widget.name}. Set your own attendance password before you can punch.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: RvmSpacing.lg),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'New attendance password',
                    helperText: 'At least 8 characters.',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                ),
                const SizedBox(height: RvmSpacing.lg),
                FilledButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Set password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<PunchBloc>().add(PunchSetPasswordRequested(_password.text));
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.today, this.shift, this.branch});
  final PunchToday? today;
  final AttendanceShift? shift;
  final AttendanceBranch? branch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final punchedIn = today?.punchedIn ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RvmSpacing.md),
      decoration: BoxDecoration(
        color: (punchedIn ? RvmColors.teamSeed : scheme.surfaceContainerHighest).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RvmRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(punchedIn ? "You're punched in" : 'Not punched in',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          if (today?.firstIn != null)
            Text('In since ${TimeOfDay.fromDateTime(today!.firstIn!.toLocal()).format(context)}',
                style: Theme.of(context).textTheme.bodyMedium),
          if (shift?.start != null)
            Text('Shift ${shift!.start}-${shift!.end}', style: Theme.of(context).textTheme.bodySmall),
          if (branch?.name != null)
            Text(
              branch!.configured ? 'At ${branch!.name}' : '${branch!.name} (location not set up)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _DeviceWarning extends StatelessWidget {
  const _DeviceWarning({this.device});
  final AttendanceDevice? device;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = switch (device?.thisPhone) {
      'other' => 'This phone is registered to someone else. Punch from your own phone.',
      'revoked' => 'HR has reset this phone. Punch from your new phone, or ask HR.',
      _ => 'This phone is not the one registered to you. Ask HR to reset it.',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: RvmSpacing.md),
      padding: const EdgeInsets.all(RvmSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(RvmRadii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.phonelink_erase_outlined, color: scheme.onErrorContainer),
          const SizedBox(width: RvmSpacing.sm),
          Expanded(
            child: Text(message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});
  final AttendanceMonthDay day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = switch (day.status) {
      'present' => RvmColors.success,
      'absent' => RvmColors.danger,
      'half_day' => RvmColors.warning,
      _ => scheme.onSurfaceVariant,
    };
    final inTime = day.firstIn == null ? '--' : TimeOfDay.fromDateTime(day.firstIn!.toLocal()).format(context);
    final outTime = day.lastOut == null ? '--' : TimeOfDay.fromDateTime(day.lastOut!.toLocal()).format(context);
    return ListTile(
      dense: true,
      leading: CircleAvatar(radius: 6, backgroundColor: colour),
      title: Text(day.day),
      subtitle: Text('${day.status} · $inTime-$outTime'),
    );
  }
}

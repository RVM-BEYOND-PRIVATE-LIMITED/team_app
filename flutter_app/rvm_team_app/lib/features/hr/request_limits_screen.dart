import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

/// C6: HR edits the monthly request limits. Backend: `GET/PUT /api/ess/hr/request-limits`.
class RequestLimitsScreen extends StatefulWidget {
  const RequestLimitsScreen({super.key});

  @override
  State<RequestLimitsScreen> createState() => _RequestLimitsScreenState();
}

class _RequestLimitsScreenState extends State<RequestLimitsScreen> {
  bool _loading = true;
  Failure? _failure;
  List<RequestLimit> _limits = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final limits = await getIt<EssRepository>().requestLimits();
      if (!mounted) return;
      setState(() {
        _limits = limits;
        _loading = false;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _failure = f;
        _loading = false;
      });
    }
  }

  Future<void> _edit(RequestLimit limit) async {
    final minutes = limit.type == 'short_leave';
    final current = minutes ? limit.limitMinutes : limit.limitCount;
    final controller = TextEditingController(text: current?.toString() ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(limit.label),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              hintText: minutes
                  ? 'Minutes (blank = no limit)'
                  : 'Count (blank = no limit)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (value == null || !mounted) return;
    final number = value.isEmpty ? null : int.tryParse(value);
    if (value.isNotEmpty && number == null) return;
    try {
      if (minutes) {
        await getIt<EssRepository>()
            .setRequestLimit(limit.type, minutes: number);
      } else {
        await getIt<EssRepository>().setRequestLimit(limit.type, count: number);
      }
      await _load();
    } on Failure catch (f) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(f.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Request limits',
            subtitle: const Text('Monthly caps per employee'),
            actions: [
              TeamHeaderAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh',
                  onPressed: _load)
            ],
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) {
      return AppError(message: _failure!.message, onRetry: _load);
    }
    if (_limits.isEmpty) {
      return const AppEmpty(icon: Icons.tune, message: 'No limits configured.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(RvmSpacing.md),
      itemCount: _limits.length,
      separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
      itemBuilder: (context, i) {
        final l = _limits[i];
        final value = l.type == 'short_leave'
            ? (l.limitMinutes == null ? 'No limit' : '${l.limitMinutes} min')
            : (l.limitCount == null ? 'No limit' : '${l.limitCount}');
        return Card(
          child: ListTile(
            title: Text(l.label),
            subtitle: Text(l.updatedByName == null
                ? value
                : '$value · set by ${l.updatedByName}'),
            trailing: IconButton(
                tooltip: 'Edit',
                onPressed: () => _edit(l),
                icon: const Icon(Icons.edit_outlined)),
          ),
        );
      },
    );
  }
}

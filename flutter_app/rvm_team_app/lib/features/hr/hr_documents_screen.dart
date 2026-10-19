import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import 'employee_picker.dart';

/// E4/E5: HR's document desk — pick an employee, verify or reject their pending documents.
class HrDocumentsScreen extends StatefulWidget {
  const HrDocumentsScreen({super.key});

  @override
  State<HrDocumentsScreen> createState() => _HrDocumentsScreenState();
}

class _HrDocumentsScreenState extends State<HrDocumentsScreen> {
  OrgCard? _employee;
  bool _loading = false;
  Failure? _failure;
  DocumentPage? _page;

  Future<void> _pick() async {
    final person = await pickEmployee(context, title: 'Documents for…');
    if (person == null || !mounted) return;
    setState(() => _employee = person);
    await _load();
  }

  Future<void> _load() async {
    final employee = _employee;
    if (employee == null) return;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final page = await getIt<EssRepository>().hrEmployeeDocuments(employee.id);
      if (!mounted) return;
      setState(() {
        _page = page;
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

  Future<void> _verify(EssDocument d) async {
    try {
      await getIt<EssRepository>().verifyDocument(_employee!.id, d.id);
      await _load();
    } on Failure catch (f) {
      _snack(f.message);
    }
  }

  Future<void> _reject(EssDocument d) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject document'),
        content: TextField(controller: controller, minLines: 2, maxLines: 3, decoration: const InputDecoration(hintText: 'Reason')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Reject')),
        ],
      ),
    );
    if (reason == null || reason.length < 3 || !mounted) return;
    try {
      await getIt<EssRepository>().rejectDocument(_employee!.id, d.id, reason);
      await _load();
    } on Failure catch (f) {
      _snack(f.message);
    }
  }

  Future<void> _open(EssDocument d) async {
    try {
      final url = await getIt<EssRepository>().hrDocumentFileUrl(_employee!.id, d.id);
      if (url == null || url.isEmpty || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await Clipboard.setData(ClipboardData(text: url));
      messenger..hideCurrentSnackBar()..showSnackBar(const SnackBar(content: Text('Secure link copied (5 minutes).')));
    } on Failure catch (f) {
      _snack(f.message);
    }
  }

  Future<void> _delete(EssDocument d) async {
    try {
      await getIt<EssRepository>().deleteDocument(_employee!.id, d.id);
      await _load();
    } on Failure catch (f) {
      _snack(f.message);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Documents desk',
            subtitle: Text(_employee?.fullName ?? 'Pick an employee'),
            actions: [
              IconButton(tooltip: 'Choose employee', onPressed: _pick, icon: const Icon(Icons.person_search)),
              if (_employee != null) IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_employee == null) {
      return Center(
        child: FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.person_search), label: const Text('Choose an employee')),
      );
    }
    if (_loading) return const AppLoading();
    if (_failure != null) return AppError(message: _failure!.message, onRetry: _load);
    final page = _page;
    if (page == null || page.documents.isEmpty) {
      return const AppEmpty(icon: Icons.folder_open, message: 'No documents uploaded.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(RvmSpacing.md),
        itemCount: page.documents.length,
        separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
        itemBuilder: (context, i) {
          final d = page.documents[i];
          final name = page.types.where((t) => t.slug == d.docType).map((t) => t.name).firstOrNull ?? d.docType;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(RvmSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(name, style: Theme.of(context).textTheme.titleMedium)),
                      Text(d.status),
                    ],
                  ),
                  Text(d.fileName, style: Theme.of(context).textTheme.bodySmall),
                  if (d.rejectionReason != null) Text('Reason: ${d.rejectionReason}'),
                  const SizedBox(height: RvmSpacing.sm),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(onPressed: () => _open(d), icon: const Icon(Icons.open_in_new, size: 16), label: const Text('Open')),
                      if (d.status == 'pending') ...[
                        FilledButton(onPressed: () => _verify(d), child: const Text('Verify')),
                        OutlinedButton(onPressed: () => _reject(d), child: const Text('Reject')),
                      ],
                      TextButton(onPressed: () => _delete(d), child: const Text('Delete')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

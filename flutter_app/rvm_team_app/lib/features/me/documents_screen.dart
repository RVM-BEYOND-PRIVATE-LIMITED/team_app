import 'dart:convert';

import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

/// Phase 2C, E4: my documents — upload by type, and HR's verification status.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  bool _loading = true;
  bool _uploading = false;
  Failure? _failure;
  DocumentPage? _page;

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
      final page = await getIt<EssRepository>().myDocuments();
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

  Future<void> _upload(DocumentType type) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final contentType = _contentType(file.extension);
    if (contentType == null) {
      _snack('Use a JPG, PNG, WebP or PDF.');
      return;
    }
    setState(() => _uploading = true);
    try {
      await getIt<EssRepository>().uploadDocument(
        docType: type.slug,
        fileName: file.name,
        contentType: contentType,
        base64: base64Encode(bytes),
      );
      await _load();
      _snack('${type.name} uploaded.');
    } on Failure catch (f) {
      _snack(f.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _open(EssDocument document) async {
    try {
      final url = await getIt<EssRepository>().documentFileUrl(document.id);
      if (url == null || url.isEmpty || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await Clipboard.setData(ClipboardData(text: url));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Secure link copied (valid for 5 minutes).')));
    } on Failure catch (f) {
      _snack(f.message);
    }
  }

  static String? _contentType(String? ext) => switch (ext?.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: 'Documents',
            subtitle: const Text('Upload and track verification'),
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
      floatingActionButton: _uploading
          ? const FloatingActionButton(
              onPressed: null, child: CircularProgressIndicator())
          : FloatingActionButton.extended(
              onPressed: () => _pickType(),
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload'),
            ),
    );
  }

  Future<void> _pickType() async {
    final types = _page?.types ?? const <DocumentType>[];
    if (types.isEmpty) return;
    final type = await showModalBottomSheet<DocumentType>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          for (final t in types)
            ListTile(
                title: Text(t.name),
                subtitle: t.isMandatory ? const Text('Mandatory') : null,
                onTap: () => Navigator.pop(context, t))
        ],
      ),
    );
    if (type != null) await _upload(type);
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) {
      return AppError(message: _failure!.message, onRetry: _load);
    }
    final page = _page!;
    final held = page.documents.map((d) => d.docType).toSet();
    final missing = page.types
        .where((t) => t.isMandatory && !held.contains(t.slug))
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RvmSpacing.md, RvmSpacing.md, RvmSpacing.md, 96),
        children: [
          if (missing.isNotEmpty) ...[
            Card(
              color: Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(RvmSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Still needed',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(missing.map((t) => t.name).join(', ')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: RvmSpacing.md),
          ],
          if (page.documents.isEmpty)
            const AppEmpty(
                icon: Icons.folder_open, message: 'No documents uploaded yet.')
          else
            for (final d in page.documents) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(page.types
                          .where((t) => t.slug == d.docType)
                          .map((t) => t.name)
                          .firstOrNull ??
                      d.docType),
                  subtitle: Text([d.fileName, d.rejectionReason]
                      .where((s) => s != null && s.isNotEmpty)
                      .join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DocStatus(status: d.status),
                      IconButton(
                        tooltip: 'Open',
                        onPressed: () => _open(d),
                        icon: const Icon(Icons.open_in_new, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: RvmSpacing.sm),
            ],
        ],
      ),
    );
  }
}

class _DocStatus extends StatelessWidget {
  const _DocStatus({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'verified' => ('Verified', RvmColors.success),
      'rejected' => ('Rejected', RvmColors.danger),
      _ => ('Pending', RvmColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

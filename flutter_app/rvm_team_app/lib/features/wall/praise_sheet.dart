import 'dart:async';
import 'dart:convert';

import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import 'bloc/wall_bloc.dart';

Future<void> showPraiseSheet(BuildContext context) {
  final bloc = context.read<WallBloc>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(value: bloc, child: const _PraiseSheet()),
  );
}

class _PraiseSheet extends StatefulWidget {
  const _PraiseSheet();

  @override
  State<_PraiseSheet> createState() => _PraiseSheetState();
}

class _PraiseSheetState extends State<_PraiseSheet> {
  final _search = TextEditingController();
  final _reason = TextEditingController();
  Timer? _debounce;
  OrgCard? _person;
  String? _badge;
  List<OrgCard> _results = const [];
  Map<String, dynamic>? _attachment;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(value.trim()));
  }

  Future<void> _run(String q) async {
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    try {
      final page = await getIt<EssRepository>().directory(query: q);
      if (!mounted) return;
      setState(() => _results = page.people);
    } on Failure {
      // Silent: the user can retype.
    }
  }

  void _submit() {
    if (_person == null) {
      _snack('Choose the colleague you are praising.');
      return;
    }
    if (_badge == null) {
      _snack('Choose a badge.');
      return;
    }
    final reason = _reason.text.trim();
    if (reason.length < 3) {
      _snack('Say why (at least 3 characters).');
      return;
    }
    context.read<WallBloc>().add(WallPraiseCreated(
          employeeId: _person!.id,
          badge: _badge!,
          reason: reason,
          attachments: _attachment == null ? null : [_attachment!],
        ));
    Navigator.of(context).pop();
  }

  Future<void> _attach() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final type = switch (file.extension?.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (type == null) {
      _snack('Use a JPG, PNG or WebP photo.');
      return;
    }
    if (bytes.length > 1024 * 1024) {
      _snack('The photo must be under 1 MB.');
      return;
    }
    setState(() => _attachment = {
          'data_base64': base64Encode(bytes),
          'content_type': type,
          'name': file.name,
        });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final badges = context.select<WallBloc, List<PraiseBadge>>((b) => b.state.settings?.badges ?? const []);
    final submitting = context.select<WallBloc, bool>((b) => b.state.submitting);
    return Padding(
      padding: EdgeInsets.only(
        left: RvmSpacing.md,
        right: RvmSpacing.md,
        top: RvmSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + RvmSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Praise a colleague', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: RvmSpacing.md),
            if (_person == null) ...[
              TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name or employee code',
                  border: OutlineInputBorder(),
                ),
              ),
              for (final p in _results.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text(p.fullName.isEmpty ? '?' : p.fullName.substring(0, 1).toUpperCase())),
                  title: Text(p.fullName),
                  subtitle: Text(p.designation ?? p.employeeCode ?? ''),
                  onTap: () => setState(() {
                    _person = p;
                    _results = const [];
                  }),
                ),
            ] else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text(_person!.fullName.isEmpty ? '?' : _person!.fullName.substring(0, 1).toUpperCase())),
                title: Text(_person!.fullName),
                subtitle: Text(_person!.designation ?? ''),
                trailing: TextButton(onPressed: () => setState(() => _person = null), child: const Text('Change')),
              ),
            if (_person != null) ...[
              const SizedBox(height: RvmSpacing.md),
              Text('Badge', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: RvmSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in badges)
                    ChoiceChip(
                      label: Text(b.label),
                      selected: _badge == b.id,
                      onSelected: (_) => setState(() => _badge = b.id),
                    ),
                ],
              ),
              const SizedBox(height: RvmSpacing.md),
              TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                maxLength: 280,
                decoration: const InputDecoration(
                  labelText: 'Why do they deserve it?',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              Row(
                children: [
                  TextButton.icon(onPressed: _attach, icon: const Icon(Icons.add_a_photo_outlined, size: 18), label: const Text('Add photo')),
                  if (_attachment != null)
                    InputChip(
                      label: Text(_attachment!['name']?.toString() ?? 'Photo'),
                      onDeleted: () => setState(() => _attachment = null),
                    ),
                ],
              ),
              const SizedBox(height: RvmSpacing.sm),
              FilledButton(
                onPressed: submitting ? null : _submit,
                child: submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Give praise'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

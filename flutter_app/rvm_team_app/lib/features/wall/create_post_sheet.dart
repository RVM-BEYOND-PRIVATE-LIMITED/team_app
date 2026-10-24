import 'dart:convert';

import 'package:core_ui/core_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app_feedback.dart';
import '../../widgets/image_crop_screen.dart';
import 'bloc/wall_bloc.dart';
import 'mention_picker.dart';

Future<void> showCreatePostSheet(BuildContext context) {
  final bloc = context.read<WallBloc>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        BlocProvider.value(value: bloc, child: const _CreatePostSheet()),
  );
}

class _CreatePostSheet extends StatefulWidget {
  const _CreatePostSheet();

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _body = TextEditingController();
  final _options = <TextEditingController>[
    TextEditingController(),
    TextEditingController()
  ];
  final List<Map<String, dynamic>> _attachments = [];
  String _scope = 'org';
  bool _poll = false;
  bool _multiple = false;
  bool _anonymous = false;
  DateTime _closes = DateTime.now().add(const Duration(days: 7));
  bool _sent = false;
  bool _sentPoll = false;

  @override
  void dispose() {
    _body.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  String get _closesIso =>
      '${_closes.year.toString().padLeft(4, '0')}-${_closes.month.toString().padLeft(2, '0')}-${_closes.day.toString().padLeft(2, '0')}';

  Future<void> _pickClose() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _closes,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _closes = picked);
  }

  Future<void> _attach() async {
    if (_attachments.length >= 5) {
      _snack('Up to five files.');
      return;
    }
    FilePickerResult? result;
    try {
      result = await FilePicker.platform
          .pickFiles(allowMultiple: true, withData: true);
    } catch (_) {
      _snack('Could not open the file picker.');
      return;
    }
    if (result == null) return;
    for (final file in result.files) {
      if (_attachments.length >= 5) break;
      final bytes = file.bytes;
      final type = _contentType(file.extension);
      if (bytes == null || type == null) continue;
      if (bytes.length > 1024 * 1024) {
        _snack('${file.name} is over 1 MB.');
        continue;
      }
      setState(() => _attachments.add({
            'data_base64': base64Encode(bytes),
            'content_type': type,
            'name': file.name,
          }));
    }
  }

  Future<void> _mention() async {
    final tag = await pickMention(context);
    if (tag == null || !mounted) return;
    final text = _body.text;
    _body.text = text.isEmpty ? tag : '$text $tag';
    _body.selection = TextSelection.collapsed(offset: _body.text.length);
  }

  static String? _contentType(String? ext) => switch (ext?.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => null,
      };

  void _submit() {
    final text = _body.text.trim();
    if (text.isEmpty) {
      _snack('Write something before posting.');
      return;
    }
    if (_poll) {
      final labels = _options
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (labels.length < 2) {
        _snack('A poll needs at least two options.');
        return;
      }
      _sent = true;
      _sentPoll = true;
      context.read<WallBloc>().add(WallPostCreated(
            body: text,
            kind: 'poll',
            scope: _scope,
            poll: {
              'options': labels,
              'multiple': _multiple,
              'anonymous': _anonymous,
              'closes_on': _closesIso,
            },
          ));
    } else {
      _sent = true;
      _sentPoll = false;
      context.read<WallBloc>().add(WallPostCreated(
            body: text,
            scope: _scope,
            attachments: _attachments.isEmpty ? null : _attachments,
          ));
    }
    // Keep the sheet open until the server answers; the listeners below pop it
    // on success and show the "Post/Poll created" toast, or keep it open on a
    // refusal with the server's message.
  }

  void _snack(String message) => showAppMessage(message);

  bool _isImage(int index) =>
      _attachments[index]['content_type'].toString().startsWith('image/');

  Future<void> _cropAttachment(int index) async {
    if (!_isImage(index)) return;
    final attachment = _attachments[index];
    final raw = attachment['data_base64']?.toString();
    if (raw == null || raw.isEmpty) return;
    final cropped = await editImageBytes(context, base64Decode(raw));
    if (!mounted || cropped == null) return;
    if (cropped.length > 1024 * 1024) {
      _snack('The cropped image must be under 1 MB.');
      return;
    }
    setState(() {
      _attachments[index] = {
        ...attachment,
        'data_base64': base64Encode(cropped),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final submitting =
        context.select<WallBloc, bool>((b) => b.state.submitting);
    return MultiBlocListener(
      listeners: [
        BlocListener<WallBloc, WallState>(
          listenWhen: (a, b) => a.actionFailure != b.actionFailure,
          listener: (context, state) {
            final failure = state.actionFailure;
            if (failure != null) showAppMessage(failure.message);
          },
        ),
        BlocListener<WallBloc, WallState>(
          listenWhen: (a, b) => a.actionNonce != b.actionNonce,
          listener: (context, state) {
            if (!_sent || state.actionNonce == 0) return;
            final poll = _sentPoll;
            Navigator.of(context).pop();
            showAppMessage(poll ? 'Poll created.' : 'Post created.');
          },
        ),
      ],
      child: Padding(
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
              Text(_poll ? 'New poll' : 'New post',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: RvmSpacing.md),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: false,
                      label: Text('Post'),
                      icon: Icon(Icons.notes)),
                  ButtonSegment(
                      value: true,
                      label: Text('Poll'),
                      icon: Icon(Icons.poll_outlined)),
                ],
                selected: {_poll},
                onSelectionChanged: (s) => setState(() => _poll = s.first),
              ),
              const SizedBox(height: RvmSpacing.md),
              TextField(
                controller: _body,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                maxLength: _poll ? 300 : 2000,
                decoration: InputDecoration(
                  hintText: _poll
                      ? 'Ask a question…'
                      : 'Share something with your team…',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_poll) ...[
                for (var i = 0; i < _options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _options[i],
                            maxLength: 120,
                            decoration: InputDecoration(
                                labelText: 'Option ${i + 1}',
                                counterText: '',
                                border: const OutlineInputBorder()),
                          ),
                        ),
                        if (_options.length > 2)
                          IconButton(
                            onPressed: () =>
                                setState(() => _options.removeAt(i).dispose()),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                      ],
                    ),
                  ),
                if (_options.length < 10)
                  OutlinedButton.icon(
                    onPressed: () =>
                        setState(() => _options.add(TextEditingController())),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add option'),
                  ),
                const SizedBox(height: RvmSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _multiple,
                  onChanged: (v) => setState(() => _multiple = v),
                  title: const Text('Allow multiple choices'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _anonymous,
                  onChanged: (v) => setState(() => _anonymous = v),
                  title: const Text('Anonymous poll'),
                  subtitle: const Text('Nobody, HR included, sees who voted.'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickClose,
                  icon: const Icon(Icons.event),
                  label: Text('Closes: $_closesIso'),
                ),
                const SizedBox(height: RvmSpacing.md),
              ] else ...[
                Row(
                  children: [
                    TextButton.icon(
                        onPressed: _attach,
                        icon: const Icon(Icons.attach_file, size: 18),
                        label: const Text('Attach')),
                    TextButton.icon(
                        onPressed: _mention,
                        icon: const Icon(Icons.alternate_email, size: 18),
                        label: const Text('Mention')),
                  ],
                ),
                if (_attachments.any(
                    (a) => a['content_type'].toString().startsWith('image/')))
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Tap an image to crop it.',
                        style:
                            TextStyle(fontSize: 10.5, color: RvmColors.muted)),
                  ),
                if (_attachments.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < _attachments.length; i++)
                        InputChip(
                          avatar: _isImage(i)
                              ? const Icon(Icons.crop_rounded, size: 14)
                              : null,
                          label: Text(
                              _attachments[i]['name']?.toString() ?? 'File'),
                          onPressed:
                              _isImage(i) ? () => _cropAttachment(i) : null,
                          onDeleted: () =>
                              setState(() => _attachments.removeAt(i)),
                        ),
                    ],
                  ),
                const SizedBox(height: RvmSpacing.sm),
              ],
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'org', label: Text('Organisation')),
                  ButtonSegment(value: 'branch', label: Text('My branch')),
                ],
                selected: {_scope},
                onSelectionChanged: (s) => setState(() => _scope = s.first),
              ),
              const SizedBox(height: RvmSpacing.md),
              FilledButton(
                onPressed: submitting ? null : _submit,
                child: submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_poll ? 'Post poll' : 'Post to the Wall'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

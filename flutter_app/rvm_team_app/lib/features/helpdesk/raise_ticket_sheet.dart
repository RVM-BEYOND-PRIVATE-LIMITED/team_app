import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/ess_models.dart';
import 'bloc/helpdesk_bloc.dart';

Future<void> showRaiseTicketSheet(BuildContext context) {
  final bloc = context.read<HelpdeskBloc>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(value: bloc, child: const _RaiseTicketSheet()),
  );
}

class _RaiseTicketSheet extends StatefulWidget {
  const _RaiseTicketSheet();

  @override
  State<_RaiseTicketSheet> createState() => _RaiseTicketSheetState();
}

class _RaiseTicketSheetState extends State<_RaiseTicketSheet> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String? _category;
  bool _anonymous = false;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit(List<HelpdeskCategory> categories) {
    final slug = _category;
    final category = categories.where((c) => c.id == slug).firstOrNull;
    if (category == null) {
      _snack('Choose a category.');
      return;
    }
    if (!category.isTicket) {
      _snack('That category uses another flow: ${category.flow ?? 'not a ticket'}.');
      return;
    }
    if (_subject.text.trim().length < 3) {
      _snack('Give a subject (at least 3 characters).');
      return;
    }
    if (_body.text.trim().length < 3) {
      _snack('Describe the issue (at least 3 characters).');
      return;
    }
    context.read<HelpdeskBloc>().add(HelpdeskTicketRaised(
          category: category.slug ?? '',
          subject: _subject.text.trim(),
          body: _body.text.trim(),
          anonymous: _anonymous,
        ));
    Navigator.of(context).pop();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.select<HelpdeskBloc, List<HelpdeskCategory>>((b) => b.state.categories);
    final submitting = context.select<HelpdeskBloc, bool>((b) => b.state.submitting);
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
            Text('Raise a ticket', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: RvmSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: [
                for (final c in categories)
                  if (c.isTicket)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
            if (categories.any((c) => !c.isTicket))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Leave, attendance fixes and assets use their own flows.',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            const SizedBox(height: RvmSpacing.md),
            TextField(
              controller: _subject,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
            ),
            const SizedBox(height: RvmSpacing.sm),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'What happened?', alignLabelWithHint: true, border: OutlineInputBorder()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _anonymous,
              onChanged: (v) => setState(() => _anonymous = v),
              title: const Text('Raise anonymously'),
              subtitle: const Text('Only HR will see who raised it.'),
            ),
            const SizedBox(height: RvmSpacing.sm),
            FilledButton(
              onPressed: submitting ? null : () => _submit(categories),
              child: submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send to the team'),
            ),
          ],
        ),
      ),
    );
  }
}

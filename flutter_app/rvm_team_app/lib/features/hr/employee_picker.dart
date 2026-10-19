import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';

/// Picks a colleague through the directory (used by the HR desks).
Future<OrgCard?> pickEmployee(BuildContext context, {String title = 'Choose an employee'}) =>
    showDialog<OrgCard>(context: context, builder: (_) => _EmployeePicker(title: title));

class _EmployeePicker extends StatefulWidget {
  const _EmployeePicker({required this.title});
  final String title;

  @override
  State<_EmployeePicker> createState() => _EmployeePickerState();
}

class _EmployeePickerState extends State<_EmployeePicker> {
  final _query = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<OrgCard> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(value.trim()));
  }

  Future<void> _run(String q) async {
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _loading = true);
    try {
      final page = await getIt<EssRepository>().directory(query: q);
      if (!mounted) return;
      setState(() {
        _results = page.people;
        _loading = false;
      });
    } on Failure {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Name or employee code'),
            ),
            if (_loading) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in _results.take(8))
                    ListTile(
                      leading: CircleAvatar(child: Text(p.fullName.isEmpty ? '?' : p.fullName.substring(0, 1).toUpperCase())),
                      title: Text(p.fullName),
                      subtitle: Text(p.employeeCode ?? p.designation ?? ''),
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

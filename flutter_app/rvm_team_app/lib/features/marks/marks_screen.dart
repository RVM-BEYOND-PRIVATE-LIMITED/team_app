import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/team_stage2_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import '../stage2/stage2_shared.dart';

/// `/work/batch/:id/marks` — one screen for the whole batch's test marks
/// (#57 items 7–9). The server decides who may edit, the maximum and the date.
class MarksScreen extends StatefulWidget {
  const MarksScreen({super.key, required this.batchId, this.batchName});
  final String batchId;
  final String? batchName;
  @override
  State<MarksScreen> createState() => _MarksScreenState();
}

class _MarksScreenState extends State<MarksScreen> {
  bool _loading = true;
  Failure? _failure;
  List<MarksRosterRow> _rows = const [];
  List<BatchTest> _tests = const [];
  final _module = TextEditingController();
  final _courseId = TextEditingController();
  final _max = TextEditingController(text: '100');
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _module.dispose();
    _courseId.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final roster = await getIt<EssRepository>().classRoster(
          batchId: widget.batchId,
          date: stage2Day(DateTime.now()));
      final tests = await stage2Repository().batchTests(widget.batchId);
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final s in roster.students)
            MarksRosterRow(
                studentId: s.id,
                name: s.fullName ?? 'Student',
                admissionNumber: s.admissionNumber ?? ''),
        ];
        _tests = tests;
        _loading = false;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_loading) return const Scaffold(body: AppLoading());
    if (_failure != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.batchName ?? 'Test marks')),
        body: stage2Failure(_failure, onRetry: _load),
      );
    }
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: Text(widget.batchName ?? 'Test marks')),
      body: ListView(
        padding: const EdgeInsets.all(RvmSpacing.md),
        children: [
          TeamCard(
            child: Column(
              children: [
                TextField(
                  controller: _module,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Module'),
                ),
                TextField(
                  controller: _courseId,
                  decoration: const InputDecoration(
                      labelText: 'Course ID', helperText: 'From the batch'),
                ),
                TextField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Maximum marks'),
                ),
                if (_tests.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        'Earlier tests: ${_tests.map((t) => '${t.moduleName} ${t.testDate}').join(', ')}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          const SizedBox(height: RvmSpacing.md),
          for (var i = 0; i < _rows.length; i++)
            _MarksRow(
              row: _rows[i],
              max: double.tryParse(_max.text) ?? 100,
              onChanged: (row) => setState(() => _rows[i] = row),
              next: i + 1 < _rows.length,
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: p.danger)),
          ],
          const SizedBox(height: RvmSpacing.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save all marks'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final max = double.tryParse(_max.text) ?? 100;
    final course = _courseId.text.trim();
    final module = _module.text.trim();
    if (course.isEmpty || module.isEmpty) {
      setState(() => _error = 'Pick the course and the module.');
      return;
    }
    for (final row in _rows) {
      if (!row.absent && (row.marks == null || row.marks! < 0 || row.marks! > max)) {
        setState(() => _error = 'Each mark is from 0 to $max.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await stage2Repository().saveTest({
        'batch_id': widget.batchId,
        'course_id': course,
        'module_name': module,
        'max_marks': max,
        'test_date': stage2Day(DateTime.now()),
        'scores': [for (final row in _rows) row.toJson()],
      }, key: 'marks-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Marks saved.')));
        Navigator.of(context).pop();
      }
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _MarksRow extends StatelessWidget {
  const _MarksRow({
    required this.row,
    required this.max,
    required this.onChanged,
    required this.next,
  });
  final MarksRosterRow row;
  final double max;
  final ValueChanged<MarksRosterRow> onChanged;
  final bool next;

  @override
  Widget build(BuildContext context) => TeamCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(row.admissionNumber,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Switch(
              value: row.absent,
              onChanged: (v) => onChanged(row.copyWith(
                  absent: v,
                  clearMarks: v)),
            ),
            SizedBox(
              width: 84,
              child: TextFormField(
                key: ValueKey('marks-${row.studentId}'),
                enabled: !row.absent,
                initialValue: row.marks?.toString() ?? '',
                keyboardType: TextInputType.number,
                textInputAction:
                    next ? TextInputAction.next : TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(hintText: 'Marks'),
                onChanged: (v) => onChanged(
                    row.copyWith(marks: v.isEmpty ? null : num.tryParse(v))),
              ),
            ),
          ],
        ),
      );
}

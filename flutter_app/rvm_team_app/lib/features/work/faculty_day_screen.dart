import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

/// Phase 2D, H7: the faculty "my day" — today's sessions (owned or covered), the indicators card
/// and the remarks still due. Backend: `GET /api/ess/me/faculty-day`.
class FacultyDayScreen extends StatefulWidget {
  const FacultyDayScreen({super.key});

  @override
  State<FacultyDayScreen> createState() => _FacultyDayScreenState();
}

class _FacultyDayScreenState extends State<FacultyDayScreen> {
  DateTime _date = DateTime.now();
  bool _loading = true;
  Failure? _failure;
  FacultyDay? _day;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _dateIso =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final day = await getIt<EssRepository>().facultyDay(date: _dateIso);
      if (!mounted) return;
      setState(() {
        _day = day;
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 62)),
      lastDate: DateTime.now().add(const Duration(days: 62)),
    );
    if (picked != null) {
      setState(() => _date = picked);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TeamPageHeader(
            title: 'My day',
            subtitle: Text(_dateIso),
            actions: [
              IconButton(tooltip: 'Pick a date', onPressed: _pickDate, icon: const Icon(Icons.event)),
              IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppLoading();
    if (_failure != null) return AppError(message: _failure!.message, onRetry: _load);
    final day = _day!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(RvmSpacing.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(RvmSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Indicators', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: RvmSpacing.sm),
                  _row('Sessions today', '${day.sessionsToday}'),
                  _row('Marked today', '${day.markedToday} (${day.todayPercentage}%)'),
                  _row('This month', '${day.monthMarked}/${day.monthExpected} (${day.monthPercentage}%)'),
                  _row('Active students', '${day.activeStudents}/${day.totalStudents}'),
                  _row('Sessions without attendance', '${day.sessionsWithoutAttendance}'),
                  if (day.pendingRemarks > 0)
                    _row('Remarks still due', '${day.pendingRemarks}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: RvmSpacing.md),
          Text('Sessions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: RvmSpacing.sm),
          if (day.sessions.isEmpty)
            const Text('No sessions on this day.')
          else
            for (final s in day.sessions) ...[
              Card(
                child: ListTile(
                  leading: Icon(s.marked ? Icons.check_circle : Icons.schedule,
                      color: s.marked ? RvmColors.success : RvmColors.warning),
                  title: Text(s.name),
                  subtitle: Text([
                    if (s.startTime != null) '${s.startTime}${s.endTime != null ? '–${s.endTime}' : ''}',
                    if (s.locationName != null) s.locationName!,
                    '${s.students} students',
                    if (s.covered) 'covered',
                  ].join(' · ')),
                  trailing: Text(s.marked ? 'Marked' : 'Not marked',
                      style: TextStyle(color: s.marked ? RvmColors.success : RvmColors.warning)),
                ),
              ),
              const SizedBox(height: RvmSpacing.sm),
            ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

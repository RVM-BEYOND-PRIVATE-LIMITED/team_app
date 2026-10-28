import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app_feedback.dart';
import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/badge_kit.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';
import '../../widgets/team_kit.dart';

/// Phase 1E, E1/E12: Summary, Job and Timeline from the HR record, plus praise (F3).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
            create: (_) =>
                getIt<LoadBloc<MyProfile>>()..add(const LoadRequested())),
        BlocProvider(
            create: (_) =>
                getIt<LoadBloc<PraisePage>>()..add(const LoadRequested())),
        BlocProvider(
          create: (_) {
            if (getIt.isRegistered<WorkExperienceBloc>()) {
              return getIt<WorkExperienceBloc>()..add(const LoadRequested());
            }
            return LoadBloc<List<WorkExperience>>(
                () async => const <WorkExperience>[]);
          },
        ),
      ],
      child: Builder(
        builder: (context) => Scaffold(
          body: BlocListener<LoadBloc<MyProfile>, LoadState<MyProfile>>(
            // A failed pull-to-refresh keeps the loaded profile on screen (the
            // loader preserves data on failure), so say why it did not update.
            listenWhen: (a, b) =>
                a.status != LoadStatus.failure &&
                b.status == LoadStatus.failure &&
                b.data != null,
            listener: (context, state) => showAppMessage(
                state.failure?.message ?? 'Could not refresh your profile.'),
            child: Column(
              children: [
                const TeamPageHeader(
                    title: 'My profile',
                    subtitle: Text('Your HR record and timeline')),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      context
                          .read<LoadBloc<MyProfile>>()
                          .add(const LoadRefreshed());
                      context
                          .read<LoadBloc<PraisePage>>()
                          .add(const LoadRefreshed());
                      context
                          .read<WorkExperienceBloc>()
                          .add(const LoadRefreshed());
                    },
                    child: ListView(
                      // First install offline shows AppError as the only child.
                      // AlwaysScrollable keeps pull-to-refresh working even
                      // when the list is too short to scroll (issue13).
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(RvmSpacing.md),
                      children: const [
                        _ProfileBody(),
                        SizedBox(height: RvmSpacing.md),
                        _AboutBody(),
                        SizedBox(height: RvmSpacing.md),
                        _ExperienceBody(),
                        SizedBox(height: RvmSpacing.md),
                        _PraiseBody()
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoadBloc<MyProfile>, LoadState<MyProfile>>(
      builder: (context, state) {
        if (state.status == LoadStatus.initial ||
            (state.status == LoadStatus.loading && state.data == null)) {
          return const SizedBox(
              height: 120, child: Center(child: CircularProgressIndicator()));
        }
        if (state.status == LoadStatus.failure && state.data == null) {
          return AppError(
            message: state.failure?.message ?? 'Could not load your profile.',
            onRetry: () =>
                context.read<LoadBloc<MyProfile>>().add(const LoadRefreshed()),
          );
        }
        final profile = state.data!;
        final e = profile.employee;
        return BlocBuilder<LoadBloc<PraisePage>, LoadState<PraisePage>>(
          builder: (context, praiseState) {
            final earned = praiseState.data?.earned ?? const <EarnedBadge>[];
            final totalEarned =
                earned.fold<int>(0, (sum, badge) => sum + badge.count);
            return Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(RvmSpacing.md),
                    child: Row(
                      children: [
                        // Single audited avatar path (TeamAvatar): dead Supabase
                        // signed URL (issue13 DNS) falls back to the initial and
                        // never reaches the framework as an image error (issue22).
                        // The gold ring is the earned-badge frame (issue 24
                        // follow-up); with no badges the avatar is unchanged.
                        EarnedBadgeFrame(
                          badgeCount: totalEarned,
                          child: TeamAvatar(
                            name: e.fullName,
                            // The ESS sends the bytes inline. Until that backend
                            // is live, an older https link is deliberately not
                            // fetched from this screen: resolving the storage
                            // host on a fresh install is the issue13 crash.
                            photoUrl: (e.photoUrl ?? '').startsWith('data:')
                                ? e.photoUrl
                                : null,
                            size: 64,
                            background:
                                RvmColors.teamSeed.withValues(alpha: 0.16),
                            foreground: RvmColors.ink,
                          ),
                        ),
                        const SizedBox(width: RvmSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.fullName,
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              if (e.designation != null) Text(e.designation!),
                              Text(
                                  [e.department?.name, e.branch?.name]
                                      .where((s) => s != null && s.isNotEmpty)
                                      .join(' · '),
                                  style: Theme.of(context).textTheme.bodySmall),
                              if (e.noticePeriod)
                                const Text('Notice period',
                                    style: TextStyle(color: RvmColors.warning)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (earned.isNotEmpty) ...[
                  const SizedBox(height: RvmSpacing.md),
                  EarnedBadgesCard(badges: earned),
                ],
                const SizedBox(height: RvmSpacing.md),
                _Section(title: 'Job', rows: [
                  if (e.employeeCode != null)
                    ('Employee code', e.employeeCode!),
                  if (e.dateOfJoining != null) ('Joined', e.dateOfJoining!),
                  if (e.dateOfJoining != null)
                    ('Work anniversary', _workAnniversary(e.dateOfJoining!)),
                  if (e.employmentStatus != null)
                    ('Status', e.employmentStatus!.replaceAll('_', ' ')),
                  if (e.manager != null) ('Reports to', e.manager!.fullName),
                ]),
                const SizedBox(height: RvmSpacing.md),
                _Section(title: 'Personal', rows: [
                  if (profile.personal.dateOfBirth != null)
                    ('Date of birth', profile.personal.dateOfBirth!),
                  if (profile.personal.bloodGroup != null)
                    ('Blood group', profile.personal.bloodGroup!),
                  if (profile.personal.addressOneLine != null)
                    ('Address', profile.personal.addressOneLine!),
                  if (profile.personal.emergencyName != null)
                    (
                      'Emergency',
                      '${profile.personal.emergencyName}${profile.personal.emergencyPhone != null ? ' · ${profile.personal.emergencyPhone}' : ''}'
                    ),
                ]),
                const SizedBox(height: RvmSpacing.md),
                _Section(title: 'Contact', rows: [
                  if (e.email != null) ('Email', e.email!),
                  if (e.phone != null) ('Phone', e.phone!),
                ]),
                if (profile.timeline.isNotEmpty) ...[
                  const SizedBox(height: RvmSpacing.md),
                  _TimelineCard(events: _importantTimeline(profile.timeline)),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// The Timeline shows only KP's milestones (issue 24), even if it is pointed at
/// an older ESS that still sends branch moves, status changes or code
/// bookkeeping: joining, increment, yearly anniversary, promotion, designation
/// change and reporting-manager change. Repeats of the same kind on the same day
/// collapse into one entry.
List<TimelineEvent> _importantTimeline(List<TimelineEvent> events) {
  const milestoneKinds = {
    'JOINING_RECORDED',
    'INCREMENT_RECORDED',
    'WORK_ANNIVERSARY',
    'PROMOTED',
    'DESIGNATION_CHANGED',
    'REPORTING_LINE_CHANGED',
  };
  const trivialTitle = 'Details updated';
  final out = <TimelineEvent>[];
  final seen = <String>{};
  for (final e in events) {
    final kind = e.kind;
    if (kind != null) {
      if (!milestoneKinds.contains(kind)) continue;
    } else if (e.title == trivialTitle) {
      continue;
    }
    final at = e.at?.toLocal();
    final day = at == null
        ? ''
        : '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
    if (!seen.add('${e.kind ?? e.title}::$day')) continue;
    out.add(e);
  }
  return out;
}

IconData _timelineIcon(String? kind) => switch (kind) {
      'JOINING_RECORDED' => Icons.work_outline_rounded,
      'PROMOTED' => Icons.military_tech_outlined,
      'DESIGNATION_CHANGED' => Icons.trending_up_rounded,
      'REPORTING_LINE_CHANGED' => Icons.swap_horiz_rounded,
      'INCREMENT_RECORDED' => Icons.payments_outlined,
      'WORK_ANNIVERSARY' => Icons.celebration_outlined,
      _ => Icons.timeline_rounded,
    };

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.events});
  final List<TimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: RvmSpacing.sm),
            for (final t in events)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_timelineIcon(t.kind),
                    size: 18, color: RvmColors.teamSeed),
                title: Text(t.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                subtitle: (t.detail == null && t.at == null)
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (t.detail != null && t.detail!.trim().isNotEmpty)
                            Text(t.detail!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(fontSize: 12, height: 1.3)),
                          if (t.at != null)
                            Text(
                                '${t.at!.toLocal().day}/${t.at!.toLocal().month}/${t.at!.toLocal().year}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontSize: 11,
                                      color: RvmColors.subtle,
                                    )),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AboutBody extends StatefulWidget {
  const _AboutBody();

  @override
  State<_AboutBody> createState() => _AboutBodyState();
}

class _AboutBodyState extends State<_AboutBody> {
  bool _loading = true;
  SocialProfile? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!getIt.isRegistered<EssRepository>()) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final data = await getIt<EssRepository>().socialProfile();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on Failure {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<SocialProfile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AboutSheet(initial: _data),
    );
    if (saved == null || !mounted) return;
    setState(() => _data = saved);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _data == null) return const SizedBox.shrink();
    final data = _data!;
    final hasAny = [
      data.about,
      data.likes,
      data.dislikes,
      data.anniversaryDate,
      data.bloodGroup
    ].any((s) => s != null && s.trim().isNotEmpty);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 19, color: RvmColors.teamSeed),
                const SizedBox(width: 7),
                Expanded(
                  child: Text('About you',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 6)),
                ),
              ],
            ),
            if (!hasAny)
              Text('Add a short about, your likes and dislikes.',
                  style: Theme.of(context).textTheme.bodySmall)
            else ...[
              if (data.about != null && data.about!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(data.about!,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (data.likes != null && data.likes!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                _SocialLine(
                    icon: Icons.thumb_up_outlined,
                    label: 'Likes',
                    value: data.likes!,
                    color: RvmColors.success),
              ],
              if (data.dislikes != null &&
                  data.dislikes!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                _SocialLine(
                    icon: Icons.thumb_down_outlined,
                    label: 'Dislikes',
                    value: data.dislikes!,
                    color: RvmColors.warning),
              ],
              if (data.bloodGroup != null && data.bloodGroup!.isNotEmpty) ...[
                const SizedBox(height: 6),
                _SocialLine(
                    icon: Icons.bloodtype_outlined,
                    label: 'Blood group',
                    value: data.bloodGroup!,
                    color: RvmColors.danger),
              ],
              if (data.anniversaryDate != null &&
                  data.anniversaryDate!.isNotEmpty) ...[
                const SizedBox(height: 6),
                _SocialLine(
                    icon: Icons.celebration_outlined,
                    label: 'Anniversary',
                    value: _prettyDate(data.anniversaryDate!),
                    color: RvmColors.teamSeed),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SocialLine extends StatelessWidget {
  const _SocialLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 7),
        SizedBox(
          width: 92,
          child: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: RvmColors.ink)),
        ),
      ],
    );
  }
}

class _AboutSheet extends StatefulWidget {
  const _AboutSheet({this.initial});
  final SocialProfile? initial;

  @override
  State<_AboutSheet> createState() => _AboutSheetState();
}

class _AboutSheetState extends State<_AboutSheet> {
  final _about = TextEditingController();
  final _likes = TextEditingController();
  final _dislikes = TextEditingController();
  DateTime? _anniversary;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _about.text = initial?.about ?? '';
    _likes.text = initial?.likes ?? '';
    _dislikes.text = initial?.dislikes ?? '';
    _anniversary = initial?.anniversaryDate == null
        ? null
        : DateTime.tryParse(initial!.anniversaryDate!);
  }

  @override
  void dispose() {
    _about.dispose();
    _likes.dispose();
    _dislikes.dispose();
    super.dispose();
  }

  Future<void> _pickAnniversary() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _anniversary ?? now,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _anniversary = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await getIt<EssRepository>().updateSocialProfile({
        'about': _about.text.trim().isEmpty ? null : _about.text.trim(),
        'likes': _likes.text.trim().isEmpty ? null : _likes.text.trim(),
        'dislikes':
            _dislikes.text.trim().isEmpty ? null : _dislikes.text.trim(),
        'anniversary_date':
            _anniversary == null ? null : _isoDate(_anniversary!),
      });
      if (mounted) Navigator.of(context).pop(saved);
    } on Failure catch (f) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = f.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit about', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: RvmSpacing.md),
            TextField(
              controller: _about,
              maxLength: 1000,
              minLines: 3,
              maxLines: 6,
              decoration:
                  const InputDecoration(labelText: 'About', counterText: ''),
            ),
            const SizedBox(height: RvmSpacing.sm),
            TextField(
              controller: _likes,
              maxLength: 500,
              decoration:
                  const InputDecoration(labelText: 'Likes', counterText: ''),
            ),
            const SizedBox(height: RvmSpacing.sm),
            TextField(
              controller: _dislikes,
              maxLength: 500,
              decoration:
                  const InputDecoration(labelText: 'Dislikes', counterText: ''),
            ),
            const SizedBox(height: RvmSpacing.sm),
            OutlinedButton.icon(
              onPressed: _pickAnniversary,
              icon: const Icon(Icons.celebration_outlined, size: 18),
              label: Text(_anniversary == null
                  ? 'Anniversary date'
                  : _prettyDate(_isoDate(_anniversary!))),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!,
                    style: const TextStyle(color: RvmColors.danger)),
              ),
            const SizedBox(height: RvmSpacing.md),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save about'),
            ),
          ],
        ),
      ),
    );
  }
}

String _workAnniversary(String joining) {
  final date = DateTime.tryParse(joining);
  if (date == null) return joining;
  final now = DateTime.now();
  var years = now.year - date.year;
  final thisYear = DateTime(now.year, date.month, date.day);
  if (thisYear.isAfter(now)) years -= 1;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final label = '${date.day} ${months[date.month - 1]}';
  return years > 0 ? '$label · $years year${years == 1 ? '' : 's'}' : label;
}

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _prettyDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

class _ExperienceBody extends StatelessWidget {
  const _ExperienceBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkExperienceBloc, LoadState<List<WorkExperience>>>(
      builder: (context, state) {
        final entries = state.data ?? const <WorkExperience>[];
        if (entries.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(RvmSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Work experience',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: RvmSpacing.sm),
                for (final entry in entries) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.business_center_outlined,
                          size: 17, color: RvmColors.teamSeed),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.company,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            Text(entry.roleTitle,
                                style: Theme.of(context).textTheme.bodyMedium),
                            Text(
                                entry.isCurrent
                                    ? '${_monthYear(entry.fromDate)} – Present'
                                    : entry.toDate == null
                                        ? _monthYear(entry.fromDate)
                                        : '${_monthYear(entry.fromDate)} – ${_monthYear(entry.toDate!)}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (entry != entries.last)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: Divider(height: 1),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static String _monthYear(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _PraiseBody extends StatelessWidget {
  const _PraiseBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoadBloc<PraisePage>, LoadState<PraisePage>>(
      builder: (context, state) {
        final page = state.data;
        if (page == null || page.praise.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(RvmSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Praise received',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: RvmSpacing.sm),
                for (final p in page.praise.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.emoji_events_outlined,
                        color: RvmColors.teamSeed),
                    title: Text(p.badgeLabel ?? 'Praise'),
                    subtitle: Text(
                        '${p.author?.fullName ?? 'Someone'}: ${p.body ?? ''}'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: RvmSpacing.sm),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                        width: 110,
                        child: Text(r.$1,
                            style: Theme.of(context).textTheme.bodySmall)),
                    Expanded(child: Text(r.$2)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

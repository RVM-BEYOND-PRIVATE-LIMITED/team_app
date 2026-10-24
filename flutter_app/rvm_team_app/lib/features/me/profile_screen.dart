import 'package:core_bloc/core_bloc.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app_feedback.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/states.dart';
import '../../widgets/team_header.dart';

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
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(RvmSpacing.md),
                      children: const [
                        _ProfileBody(),
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
        return Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(RvmSpacing.md),
                child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor:
                        RvmColors.teamSeed.withValues(alpha: 0.16),
                    // Image.network with an errorBuilder: a dead avatar URL
                    // (offline DNS, expired signed link) falls back to the
                    // initial instead of reporting an image error.
                    child: (e.photoUrl == null || e.photoUrl!.isEmpty)
                        ? Text(e.fullName.isEmpty
                            ? '?'
                            : e.fullName.substring(0, 1).toUpperCase())
                        : ClipOval(
                            child: Image.network(
                              e.photoUrl!,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Text(
                                  e.fullName.isEmpty
                                      ? '?'
                                      : e.fullName
                                          .substring(0, 1)
                                          .toUpperCase()),
                            ),
                          ),
                  ),
                    const SizedBox(width: RvmSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.fullName,
                              style: Theme.of(context).textTheme.titleLarge),
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
            const SizedBox(height: RvmSpacing.md),
            _Section(title: 'Job', rows: [
              if (e.employeeCode != null) ('Employee code', e.employeeCode!),
              if (e.dateOfJoining != null) ('Joined', e.dateOfJoining!),
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
  }
}

/// The Timeline shows milestones, not every HR save. The backend maps every
/// trivial employee update to the single line "Details updated"
/// (`policy/me.js` `timelineTitle`), so that exact line is dropped here, and
/// repeats of the same line on the same day collapse into one entry.
/// The permanent fix is a stable `kind` on the timeline items (raised to KP);
/// this keeps the exact server wording out of any other matching.
List<TimelineEvent> _importantTimeline(List<TimelineEvent> events) {
  const trivial = 'Details updated';
  final out = <TimelineEvent>[];
  final seen = <String>{};
  for (final e in events) {
    if (e.title == trivial) continue;
    final at = e.at?.toLocal();
    final day =
        at == null ? '' : '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
    if (!seen.add('${e.title}::$day')) continue;
    out.add(e);
  }
  return out;
}

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
                leading: const Icon(Icons.timeline, size: 18),
                title: Text(t.title),
                subtitle: t.at == null
                    ? null
                    : Text(
                        '${t.at!.toLocal().day}/${t.at!.toLocal().month}/${t.at!.toLocal().year}'),
              ),
          ],
        ),
      ),
    );
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

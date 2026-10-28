import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/badge_kit.dart';
import '../../widgets/team_kit.dart';

Future<void> showColleagueProfile(BuildContext context, OrgCard person) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ColleagueProfileSheet(person: person),
  );
}

class _ColleagueProfileSheet extends StatefulWidget {
  const _ColleagueProfileSheet({required this.person});
  final OrgCard person;

  @override
  State<_ColleagueProfileSheet> createState() => _ColleagueProfileSheetState();
}

class _ColleagueProfileSheetState extends State<_ColleagueProfileSheet> {
  bool _loading = true;
  Failure? _failure;
  ColleagueProfile? _profile;
  PraisePage? _praise;

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
    final repo = getIt<EssRepository>();
    ColleagueProfile? profile;
    PraisePage? praise;
    Failure? failure;
    try {
      profile = await repo.colleagueProfile(widget.person.id);
    } on Failure catch (f) {
      failure = f;
    }
    try {
      praise = await repo.myPraise(employeeId: widget.person.id);
    } on Failure catch (f) {
      failure ??= f;
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _praise = praise;
      _failure = profile == null && praise == null ? failure : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final person = _profile?.person ?? widget.person;
    final photoUrl = _profile?.photoUrl;
    final badges = _profile?.badges ?? const <EarnedBadge>[];
    final badgeCount = badges.fold<int>(0, (sum, badge) => sum + badge.count);
    final praise = _praise?.praise ?? const <WallPost>[];
    final height = MediaQuery.of(context).size.height * 0.9;
    return SizedBox(
      height: height,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              RvmSpacing.md, 0, RvmSpacing.md, RvmSpacing.lg),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Refresh profile',
                onPressed: _load,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh_rounded,
                    size: 19, color: RvmColors.muted),
              ),
            ),
            _Header(
              person: person,
              photoUrl: photoUrl,
              badgeCount: badgeCount,
            ),
            const SizedBox(height: RvmSpacing.md),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_failure != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: RvmSpacing.sm),
                  child: Text(
                    _failure!.message,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (badges.isNotEmpty) ...[
                EarnedBadgesCard(badges: badges),
                const SizedBox(height: RvmSpacing.md),
              ],
              _DetailsCard(profile: _profile, person: person),
              const SizedBox(height: RvmSpacing.md),
              _AboutCard(profile: _profile),
              const SizedBox(height: RvmSpacing.md),
              _ExperienceCard(
                  entries:
                      _profile?.workExperience ?? const <WorkExperience>[]),
              if (praise.isNotEmpty) ...[
                const SizedBox(height: RvmSpacing.md),
                _PraiseCard(posts: praise),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.person,
    required this.photoUrl,
    required this.badgeCount,
  });

  final OrgCard person;
  final String? photoUrl;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final subtitle = [
      person.designation,
      person.department?.name,
    ].where((s) => s != null && s.isNotEmpty).join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          children: [
            EarnedBadgeFrame(
              badgeCount: badgeCount,
              child: TeamAvatar(
                name: person.fullName,
                photoUrl: photoUrl,
                size: 88,
                background: RvmColors.teamSeed.withValues(alpha: 0.16),
                foreground: RvmColors.ink,
              ),
            ),
            const SizedBox(height: RvmSpacing.sm),
            Text(person.fullName,
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subtitle,
                  textAlign: TextAlign.center, style: text.bodySmall),
            ],
            if (person.branch?.name != null) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 13, color: RvmColors.subtle),
                  const SizedBox(width: 3),
                  Text(person.branch!.name, style: text.labelSmall),
                ],
              ),
            ],
            if (person.noticePeriod) ...[
              const SizedBox(height: 8),
              const TeamPill(
                  label: 'Notice period', tone: TeamPillTone.warning),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.profile, required this.person});
  final ColleagueProfile? profile;
  final OrgCard person;

  @override
  Widget build(BuildContext context) {
    final anniversary = profile?.anniversaryDate;
    final rows = <(IconData, String, String, Color)>[
      (
        Icons.work_history_outlined,
        'Date of joining',
        profile?.dateOfJoining != null
            ? _prettyDay(profile!.dateOfJoining!)
            : 'Not recorded',
        RvmColors.teamSeed
      ),
      (
        Icons.celebration_outlined,
        'Work anniversary',
        profile?.dateOfJoining != null
            ? _anniversaryText(profile!.dateOfJoining!)
            : 'Not recorded',
        RvmColors.warning
      ),
      (
        Icons.cake_outlined,
        'Date of birth',
        profile?.dateOfBirth != null
            ? _prettyDay(profile!.dateOfBirth!)
            : 'Not recorded',
        RvmColors.info
      ),
      (
        Icons.bloodtype_outlined,
        'Blood group',
        profile?.bloodGroup?.isNotEmpty == true
            ? profile!.bloodGroup!
            : 'Not set',
        RvmColors.danger
      ),
      (
        Icons.celebration_outlined,
        'Anniversary',
        anniversary != null && anniversary.isNotEmpty
            ? _prettyDay(anniversary)
            : 'Not set',
        RvmColors.teamSeed
      ),
      (
        Icons.badge_outlined,
        'Employee code',
        person.employeeCode ?? 'Not recorded',
        RvmColors.teamSeed
      ),
      (
        Icons.account_tree_outlined,
        'Department',
        person.department?.name ?? 'Not recorded',
        RvmColors.teamSeed
      ),
      (
        Icons.location_city_outlined,
        'Branch',
        person.branch?.name ?? 'Not recorded',
        RvmColors.teamSeed
      ),
      (
        Icons.alternate_email_rounded,
        'Email',
        person.email ?? 'Not shared',
        RvmColors.info
      ),
      (
        person.phone != null ? Icons.phone_outlined : Icons.lock_outline,
        'Phone',
        person.phone ?? 'Visible to managers/HR only',
        person.phone != null ? RvmColors.success : RvmColors.muted
      ),
      (
        Icons.work_outline_rounded,
        'Status',
        person.employmentStatus?.replaceAll('_', ' ') ?? 'Not recorded',
        RvmColors.muted
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Details',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: RvmSpacing.sm),
            for (final (icon, label, value, color) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 17, color: color),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 105,
                      child: Text(label,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                    Expanded(
                      child: Text(value,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _anniversaryText(String joining) {
  final date = DateTime.tryParse(joining);
  if (date == null) return _prettyDay(joining);
  final now = DateTime.now();
  var years = now.year - date.year;
  final thisYear = DateTime(now.year, date.month, date.day);
  if (thisYear.isAfter(now)) years -= 1;
  final at = _prettyDay(joining);
  return years > 0 ? '$at · $years year${years == 1 ? '' : 's'}' : at;
}

String _experienceDates(WorkExperience entry) {
  final from = _monthYear(entry.fromDate);
  if (entry.isCurrent) return '$from – Present';
  if (entry.toDate == null) return from;
  return '$from – ${_monthYear(entry.toDate!)}';
}

String _monthYear(String value) {
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

String _prettyDay(String value) {
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

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.profile});
  final ColleagueProfile? profile;

  @override
  Widget build(BuildContext context) {
    final about = profile?.about?.trim();
    final likes = profile?.likes?.trim();
    final dislikes = profile?.dislikes?.trim();
    final anniversary = profile?.anniversaryDate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              about == null || about.isEmpty ? 'Not added yet.' : about,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: about == null || about.isEmpty
                      ? RvmColors.subtle
                      : RvmColors.ink),
            ),
            const SizedBox(height: 8),
            _SocialRow(
                icon: Icons.thumb_up_outlined,
                label: 'Likes',
                value: likes == null || likes.isEmpty ? 'Not added' : likes,
                color: RvmColors.success),
            const SizedBox(height: 6),
            _SocialRow(
                icon: Icons.thumb_down_outlined,
                label: 'Dislikes',
                value: dislikes == null || dislikes.isEmpty
                    ? 'Not added'
                    : dislikes,
                color: RvmColors.warning),
            const SizedBox(height: 6),
            _SocialRow(
                icon: Icons.bloodtype_outlined,
                label: 'Blood group',
                value: profile?.bloodGroup?.isNotEmpty == true
                    ? profile!.bloodGroup!
                    : 'Not set',
                color: RvmColors.danger),
            const SizedBox(height: 6),
            _SocialRow(
                icon: Icons.celebration_outlined,
                label: 'Anniversary',
                value: anniversary != null && anniversary.isNotEmpty
                    ? _prettyDay(anniversary)
                    : 'Not set',
                color: RvmColors.teamSeed),
          ],
        ),
      ),
    );
  }
}

class _SocialRow extends StatelessWidget {
  const _SocialRow({
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

class _ExperienceCard extends StatelessWidget {
  const _ExperienceCard({required this.entries});
  final List<WorkExperience> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.business_center_outlined,
                    size: 18, color: RvmColors.teamSeed),
                const SizedBox(width: 6),
                Text('Work experience',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: RvmSpacing.sm),
            if (entries.isEmpty)
              Text('No work experience added yet.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: RvmColors.subtle)),
            for (final entry in entries) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: const BoxDecoration(
                        color: RvmColors.teamSeed, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
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
                        Text(_experienceDates(entry),
                            style: Theme.of(context).textTheme.bodySmall),
                        if (entry.location != null &&
                            entry.location!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(entry.location!,
                                style: Theme.of(context).textTheme.labelSmall),
                          ),
                        if (entry.description != null &&
                            entry.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(entry.description!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (entry != entries.last)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PraiseCard extends StatelessWidget {
  const _PraiseCard({required this.posts});
  final List<WallPost> posts;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RvmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Praise received',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: RvmSpacing.sm),
            for (final post in posts.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.emoji_events_outlined,
                        size: 18, color: RvmColors.teamSeed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${post.badgeLabel ?? 'Praise'} · ${post.author?.fullName ?? 'A colleague'}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          if (post.body != null && post.body!.isNotEmpty)
                            Text(post.body!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

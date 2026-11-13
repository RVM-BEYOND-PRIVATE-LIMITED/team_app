import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../../auth/team_permissions.dart';

// The Home cards and the Me tiles, each with the rule that decides who sees it
// (team_app #50, item 6). The screens draw what these lists return, in order.

bool _everyone(TeamViewer _) => true;

/// A portal sign-in. An attendance-only punch token is refused by the
/// Scheduler everywhere except the punch routes, so Scheduler reads are hidden
/// from it.
bool _portal(TeamViewer v) => !v.attendance;

// ── Home ──────────────────────────────────────────────────────────────────

/// The cards Home can show, top to bottom.
enum HomeCard {
  schedule,
  offThisWeek,
  faculty,
  hod,
  priorityTasks,
  interviews,
  quickActions,
  workFromHome,
  announcements,
}

class HomeCardSpec {
  const HomeCardSpec(this.card, this.visible);

  final HomeCard card;
  final bool Function(TeamViewer viewer) visible;
}

/// Home's cards in order. Interviews, priority tasks and announcements are
/// Scheduler reads, so they are for portal sign-ins only; the ESS cards work
/// for everyone.
final List<HomeCardSpec> homeCardRegistry = [
  const HomeCardSpec(HomeCard.schedule, _everyone),
  const HomeCardSpec(HomeCard.offThisWeek, _everyone),
  HomeCardSpec(HomeCard.faculty, (v) => v.perms.canSeeFacultyWork),
  HomeCardSpec(HomeCard.hod, (v) => v.perms.canSeeHodWork),
  HomeCardSpec(HomeCard.priorityTasks,
      (v) => _portal(v) && v.perms.canSeePriorityTasks),
  HomeCardSpec(
      HomeCard.interviews, (v) => _portal(v) && v.perms.canSeeInterviews),
  const HomeCardSpec(HomeCard.quickActions, _everyone),
  const HomeCardSpec(HomeCard.workFromHome, _portal),
  HomeCardSpec(HomeCard.announcements,
      (v) => _portal(v) && v.perms.canSeeAnnouncements),
];

/// The Home cards [viewer] sees, in order.
List<HomeCard> homeCardsFor(TeamViewer viewer) => [
      for (final spec in homeCardRegistry)
        if (spec.visible(viewer)) spec.card,
    ];

// ── Me ────────────────────────────────────────────────────────────────────

/// A row on Me: what it says, where it goes and who sees it.
class MeTileSpec {
  const MeTileSpec({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.attendanceSubtitle,
    this.visible = _everyone,
  });

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;

  /// Shown instead of [subtitle] to an attendance-only sign-in.
  final String? attendanceSubtitle;
  final String route;
  final bool Function(TeamViewer viewer) visible;
}

class MeSectionSpec {
  const MeSectionSpec(this.title, this.tiles);

  final String title;
  final List<MeTileSpec> tiles;
}

/// One row on Me, resolved for a viewer.
class MeTile {
  const MeTile({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

/// One section on Me, holding only the tiles the viewer sees.
class MeSection {
  const MeSection(this.title, this.tiles);

  final String title;
  final List<MeTile> tiles;
}

/// Me's sections in order. A section left with no tile for the viewer is not
/// shown: an attendance-only sign-in gets no Work section, as before.
final List<MeSectionSpec> meSectionRegistry = [
  const MeSectionSpec('Me', [
    MeTileSpec(
        id: 'punch',
        icon: Icons.fingerprint,
        title: 'Punch in / out',
        subtitle: 'Geofenced punch, remarks',
        route: '/me/punch'),
    MeTileSpec(
        id: 'my-day',
        icon: Icons.today_outlined,
        title: 'My day',
        subtitle: 'Today from the server’s clock, HR’s remark',
        route: '/me/attendance'),
    MeTileSpec(
        id: 'work-profile',
        icon: Icons.person_outline,
        title: 'Work profile',
        subtitle: 'Summary, job and timeline',
        route: '/me/profile'),
    MeTileSpec(
        id: 'personal',
        icon: Icons.badge_outlined,
        title: 'Personal details',
        subtitle: 'Blood group, emergency contact',
        route: '/me/personal'),
    MeTileSpec(
        id: 'documents',
        icon: Icons.folder_open_outlined,
        title: 'Documents',
        subtitle: 'Upload and track verification',
        route: '/me/documents'),
    MeTileSpec(
        id: 'bank',
        icon: Icons.account_balance_outlined,
        title: 'Bank details',
        subtitle: 'Saved with your consent',
        route: '/me/bank'),
    MeTileSpec(
        id: 'id-card',
        icon: Icons.badge,
        title: 'ID card',
        subtitle: 'Your employee card and verify link',
        route: '/me/id-card'),
    MeTileSpec(
        id: 'change-requests',
        icon: Icons.edit_note,
        title: 'Profile changes',
        subtitle: 'Ask HR to correct your record',
        route: '/me/change-requests'),
    MeTileSpec(
        id: 'data-requests',
        icon: Icons.privacy_tip_outlined,
        title: 'Data requests',
        subtitle: 'Correct or delete your data',
        route: '/me/data-requests'),
  ]),
  MeSectionSpec('Work', [
    MeTileSpec(
        id: 'batches',
        icon: Icons.menu_book_outlined,
        title: 'My batches',
        subtitle: 'Mark student attendance',
        route: '/work/batches',
        visible: _teaching),
    MeTileSpec(
        id: 'faculty-day',
        icon: Icons.today_outlined,
        title: 'My day (faculty)',
        subtitle: 'Today\'s sessions and indicators',
        route: '/work/my-day',
        visible: _teaching),
    MeTileSpec(
        id: 'indicators',
        icon: Icons.insights_outlined,
        title: 'My indicators',
        subtitle: 'Attendance health across my sessions',
        route: '/work/indicators',
        visible: _teaching),
    MeTileSpec(
        id: 'leaders',
        icon: Icons.insights,
        title: 'Leaders overview',
        subtitle: 'Headcount, attendance and the approval queue',
        route: '/leaders',
        visible: (v) =>
            _portal(v) &&
            (v.role == AppRole.ceo || v.role == AppRole.superAdmin)),
    MeTileSpec(
        id: 'faculty-development',
        icon: Icons.school_outlined,
        title: 'Faculty Development',
        subtitle: 'To-do, risk logs, verdicts, comments',
        route: '/work/hod',
        visible: (v) => _portal(v) && v.perms.canSeeHodWork),
    MeTileSpec(
        id: 'interviews',
        icon: Icons.event_note_outlined,
        title: 'Interviews',
        subtitle: 'Your next rounds as a panel member',
        route: '/work/interviews',
        visible: (v) => _portal(v) && v.perms.canSeeInterviews),
    MeTileSpec(
        id: 'hr-tools',
        icon: Icons.admin_panel_settings_outlined,
        title: 'HR tools',
        subtitle: 'Requests, location reports, phones',
        route: '/hr/tools',
        visible: (v) => _portal(v) && (v.caps?.canSeeHrTools ?? false)),
  ]),
  const MeSectionSpec('Account', [
    // The same route serves both kinds of sign-in: the screen shows the
    // Scheduler card for a portal session and the ESS card (password only;
    // email/phone are HR-managed) for an attendance session.
    MeTileSpec(
        id: 'account-security',
        icon: Icons.shield_outlined,
        title: 'Account & security',
        subtitle: 'Password, email, phone, two-factor',
        attendanceSubtitle: 'Password; email and phone via HR',
        route: '/account/security'),
    MeTileSpec(
        id: 'sessions',
        icon: Icons.devices_other_outlined,
        title: 'Signed-in devices',
        subtitle: 'Sign out other phones',
        route: '/me/sessions'),
    MeTileSpec(
        id: 'security-events',
        icon: Icons.history,
        title: 'Security activity',
        subtitle: 'Recent sign-ins and changes',
        route: '/account/security-events',
        visible: _portal),
  ]),
  const MeSectionSpec('Support', [
    MeTileSpec(
        id: 'helpdesk',
        icon: Icons.support_agent,
        title: 'Helpdesk',
        subtitle: 'Raise a ticket and follow its thread',
        route: '/helpdesk'),
  ]),
];

bool _teaching(TeamViewer v) => _portal(v) && v.perms.canSeeFacultyWork;

/// The Me sections [viewer] sees, in order, each with its visible tiles.
List<MeSection> meSectionsFor(TeamViewer viewer) => [
      for (final section in meSectionRegistry)
        if (_tilesFor(section, viewer) case final tiles when tiles.isNotEmpty)
          MeSection(section.title, tiles),
    ];

List<MeTile> _tilesFor(MeSectionSpec section, TeamViewer viewer) => [
      for (final spec in section.tiles)
        if (spec.visible(viewer))
          MeTile(
            id: spec.id,
            icon: spec.icon,
            title: spec.title,
            subtitle: viewer.attendance
                ? (spec.attendanceSubtitle ?? spec.subtitle)
                : spec.subtitle,
            route: spec.route,
          ),
    ];

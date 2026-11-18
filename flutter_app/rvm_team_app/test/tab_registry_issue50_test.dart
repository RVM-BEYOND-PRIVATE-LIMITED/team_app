import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/auth/team_permissions.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/shell/tab_registry.dart';
import 'package:rvm_team_app/features/shell/tile_registry.dart';

/// team_app #50, item 6: the tab, Home-card and Me-tile registries draw
/// exactly what the hand-written shell, Home and Me drew before, for every role
/// and both kinds of sign-in. The only change is the sales role (item 4).
EssCapabilities _caps({
  List<String> tabs = const ['home', 'inbox', 'wall', 'team', 'me'],
  List<String> hrScope = const [],
  bool anyRequest = false,
}) =>
    EssCapabilities(
      tabs: tabs,
      sectionTime: true,
      sectionHelpdesk: true,
      sectionDocuments: true,
      sectionProfile: true,
      sectionWork: false,
      hasReports: false,
      directReports: 0,
      approvalsOwnReports: false,
      approvalsAnyRequest: anyRequest,
      approvalRequestTypes: const [],
      hrScope: hrScope,
      wallPost: true,
      wallAnnounce: false,
      wallModerate: false,
      pushEnabled: true,
      integrityRequired: false,
    );

final _capsCases = <EssCapabilities>[
  _caps(),
  _caps(tabs: const []),
  _caps(tabs: const ['home', 'me']),
  _caps(tabs: const ['inbox']),
  _caps(hrScope: const ['documents']),
  _caps(anyRequest: true),
];

// ── The shell, Home and Me as they were written before the registries ───────

List<(String, IconData)> _tabsBefore(
    AppRole role, bool attendance, EssCapabilities caps) {
  const all = ['home', 'inbox', 'wall', 'team', 'me'];
  final teaching = TeamPermissions.forRole(role).canSeeFacultyWork;
  final allowed = caps.tabs.isEmpty ? all : caps.tabs;
  final entries = [
    if (allowed.contains('home')) ('Home', Icons.home_outlined),
    if (!attendance && allowed.contains('inbox'))
      (
        teaching ? 'Attendance' : 'Inbox',
        teaching ? Icons.fact_check_outlined : Icons.inbox_outlined
      ),
    if (allowed.contains('wall')) ('Wall', Icons.forum_outlined),
    if (allowed.contains('team')) ('My Team', Icons.groups_outlined),
    if (allowed.contains('me')) ('Me', Icons.person_outline_rounded),
  ];
  return entries.isEmpty ? [('Home', Icons.home_outlined)] : entries;
}

List<HomeCard> _homeBefore(AppRole role, bool attendance) {
  final perms = TeamPermissions.forRole(role);
  return [
    HomeCard.schedule,
    HomeCard.offThisWeek,
    if (perms.canSeeFacultyWork) HomeCard.faculty,
    if (perms.canSeeHodWork) HomeCard.hod,
    if (!attendance && perms.canSeePriorityTasks) HomeCard.priorityTasks,
    if (!attendance) ...[
      HomeCard.interviews,
      HomeCard.quickActions,
      HomeCard.workFromHome,
      HomeCard.announcements,
    ] else
      HomeCard.quickActions,
  ];
}

List<(String, List<(String, String, String)>)> _meBefore(
    AppRole role, bool attendance, EssCapabilities caps) {
  final perms = TeamPermissions.forRole(role);
  return [
    (
      'Me',
      const [
        ('Punch in / out', 'Geofenced punch, remarks', '/me/punch'),
        (
          'My day',
          'Today from the server’s clock, HR’s remark',
          '/me/attendance'
        ),
        ('Work profile', 'Summary, job and timeline', '/me/profile'),
        ('Personal details', 'Blood group, emergency contact', '/me/personal'),
        ('Documents', 'Upload and track verification', '/me/documents'),
        ('Bank details', 'Saved with your consent', '/me/bank'),
        ('ID card', 'Your employee card and verify link', '/me/id-card'),
        (
          'Profile changes',
          'Ask HR to correct your record',
          '/me/change-requests'
        ),
        ('Data requests', 'Correct or delete your data', '/me/data-requests'),
      ]
    ),
    if (!attendance)
      (
        'Work',
        [
          if (perms.canSeeFacultyWork) ...[
            ('My batches', 'Mark student attendance', '/work/batches'),
            (
              'My day (faculty)',
              'Today\'s sessions and indicators',
              '/work/my-day'
            ),
            (
              'My indicators',
              'Attendance health across my sessions',
              '/work/indicators'
            ),
          ],
          if (role == AppRole.ceo || role == AppRole.superAdmin)
            (
              'Leaders overview',
              'Headcount, attendance and the approval queue',
              '/leaders'
            ),
          if (perms.canSeeHodWork)
            (
              'Faculty Development',
              'To-do, risk logs, verdicts, comments',
              '/work/hod'
            ),
          (
            'Interviews',
            'Your next rounds as a panel member',
            '/work/interviews'
          ),
          if (caps.canSeeHrTools)
            ('HR tools', 'Requests, location reports, phones', '/hr/tools'),
        ]
      ),
    (
      'Account',
      [
        (
          'Account & security',
          attendance
              ? 'Password; email and phone via HR'
              : 'Password, email, phone, two-factor',
          '/account/security'
        ),
        ('Signed-in devices', 'Sign out other phones', '/me/sessions'),
        if (!attendance)
          (
            'Security activity',
            'Recent sign-ins and changes',
            '/account/security-events'
          ),
      ]
    ),
    (
      'Support',
      const [
        ('Helpdesk', 'Raise a ticket and follow its thread', '/helpdesk'),
      ]
    ),
  ];
}

List<(String, IconData)> _tabsNow(TeamViewer viewer) =>
    [for (final t in teamTabsFor(viewer)) (t.label, t.icon)];

List<(String, List<(String, String, String)>)> _meNow(TeamViewer viewer) => [
      for (final s in meSectionsFor(viewer))
        (s.title, [for (final t in s.tiles) (t.title, t.subtitle, t.route)]),
    ];

/// Records compare their fields with `==`, which is identity for a list, so
/// the sections are flattened into lists that `expect` compares item by item.
List<List<Object>> _flat(
        List<(String, List<(String, String, String)>)> sections) =>
    [
      for (final (title, tiles) in sections) [title, ...tiles],
    ];

void main() {
  final rolesBefore =
      AppRole.values.where((r) => r != AppRole.salesExecutive).toList();

  group('the registries keep today\'s UI for every existing role', () {
    test('tabs', () {
      for (final role in rolesBefore) {
        for (final attendance in [false, true]) {
          for (final caps in _capsCases) {
            final viewer =
                TeamViewer(role: role, attendance: attendance, caps: caps);
            expect(_tabsNow(viewer), _tabsBefore(role, attendance, caps),
                reason: '$role attendance=$attendance tabs=${caps.tabs}');
          }
        }
      }
    });

    test('Home cards', () {
      for (final role in rolesBefore) {
        for (final attendance in [false, true]) {
          expect(homeCardsFor(TeamViewer(role: role, attendance: attendance)),
              _homeBefore(role, attendance),
              reason: '$role attendance=$attendance');
        }
      }
    });

    test('Me sections and tiles', () {
      for (final role in rolesBefore) {
        for (final attendance in [false, true]) {
          for (final caps in _capsCases) {
            final viewer =
                TeamViewer(role: role, attendance: attendance, caps: caps);
            expect(
                _flat(_meNow(viewer)), _flat(_meBefore(role, attendance, caps)),
                reason: '$role attendance=$attendance caps=${caps.hrScope}');
          }
        }
      }
    });

    test('a teaching role keeps its Attendance tab and its selected icon', () {
      final tabs =
          teamTabsFor(TeamViewer(role: AppRole.faculty, caps: _caps()));
      final inbox = tabs.singleWhere((t) => t.id == 'inbox');
      expect(inbox.label, 'Attendance');
      expect(inbox.selectedIcon, Icons.fact_check_rounded);
      expect([for (final t in tabs) t.id],
          ['home', 'inbox', 'wall', 'team', 'me']);
    });

    test('an attendance-only sign-in has no Inbox, as before', () {
      final tabs = teamTabsFor(
          TeamViewer(role: AppRole.unknown, attendance: true, caps: _caps()));
      expect(
          [for (final t in tabs) t.label], ['Home', 'Wall', 'My Team', 'Me']);
    });

    test('nothing allowed still leaves Home', () {
      final tabs = teamTabsFor(TeamViewer(
          role: AppRole.unknown,
          attendance: true,
          caps: _caps(tabs: const ['inbox'])));
      expect([for (final t in tabs) t.id], ['home']);
    });
  });

  group('the sales role (item 4)', () {
    test('has no Inbox tab', () {
      for (final caps
          in _capsCases.where((c) => c.tabs.isEmpty || c.tabs.length == 5)) {
        final tabs =
            teamTabsFor(TeamViewer(role: AppRole.salesExecutive, caps: caps));
        expect(
            [for (final t in tabs) t.label], ['Home', 'Wall', 'My Team', 'Me']);
      }
    });

    test('Home has no Interviews card and no Scheduler announcements', () {
      expect(homeCardsFor(TeamViewer(role: AppRole.salesExecutive)), [
        HomeCard.schedule,
        HomeCard.offThisWeek,
        HomeCard.quickActions,
        HomeCard.workFromHome,
      ]);
    });

    test('Me has no Interviews tile and no empty Work section', () {
      final sections = meSectionsFor(
          TeamViewer(role: AppRole.salesExecutive, caps: _caps()));
      expect([for (final s in sections) s.title], ['Me', 'Account', 'Support']);
      final tiles = [for (final s in sections) ...s.tiles.map((t) => t.id)];
      expect(tiles, isNot(contains('interviews')));
      expect(tiles, contains('security-events'));
    });

    test('Work comes back when the ESS gives the sales login HR tools', () {
      final sections = meSectionsFor(TeamViewer(
          role: AppRole.salesExecutive,
          caps: _caps(hrScope: const ['documents'])));
      final work = sections.singleWhere((s) => s.title == 'Work');
      expect([for (final t in work.tiles) t.id], ['hr-tools']);
    });

    test('every other role keeps Interviews and announcements', () {
      for (final role in rolesBefore) {
        final perms = TeamPermissions.forRole(role);
        expect(perms.canSeeInterviews, isTrue, reason: '$role');
        expect(perms.canSeeInbox, isTrue, reason: '$role');
        expect(perms.canSeeAnnouncements, isTrue, reason: '$role');
      }
      final sales = TeamPermissions.forRole(AppRole.salesExecutive);
      expect(sales.canSeeInterviews, isFalse);
      expect(sales.canSeeInbox, isFalse);
      expect(sales.canSeeAnnouncements, isFalse);
      expect(sales.canSeePriorityTasks, isFalse);
      expect(sales.canSeeFacultyWork, isFalse);
      expect(sales.canSeeHodWork, isFalse);
    });
  });
}

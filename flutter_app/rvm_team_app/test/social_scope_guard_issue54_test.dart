import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/router/module_routes.dart';

import 'support/source_scan.dart';

/// team_app #54, item 13 ("Not built"): the tasks and social modules have no
/// upload, capture or posting, show no performance numbers, and have no
/// approval, chat or editor scorecard.
///
/// What is scanned comes from the registries (test/support/source_scan.dart):
/// every route the router has at or under `TeamModule.tasks` (`/tasks`) and
/// `TeamModule.social` (`/social`), and the module's own files: every Dart
/// file under lib/features/tasks/ and lib/features/social/, the file that
/// declares each of those routes' screens, and every file they import that no
/// other part of the app imports (their blocs, repositories, data sources and
/// models, wherever they live; `moduleOwnedFiles`). Comments never count.
///
/// The guard fails on:
/// * (a) an upload, capture or posting package (file_picker, image_picker,
///   camera, video_player, share_plus) or a multipart body (MultipartFile,
///   MultipartRequest, FormData), in the module's files or anything they
///   import, and a name in the module's own files that uploads
///   (`uploadPhoto`, `UploadSheet`);
/// * (b) a field, name or JSON key for a performance number: one that is
///   the word alone (`views`, `likes`, 'reach'), one that pairs it with a
///   count, rate or total (`likesCount`, 'view_rate', `totalPlays`), and
///   impressions, engagement, followers, watch_time and ctr wherever they
///   stand. A private name of the word alone (`_views`, an IndexedStack's
///   pages) and a word with another in front (`pendingSaves`) are something
///   else: a number from the server comes in through a JSON key and a
///   model's field, which are still caught;
/// * (c) an approval, chat or scorecard screen, route or control: a type
///   named for one (`ApprovalQueueScreen`, `ChatBloc`, `EditorScorecardTab`),
///   a route or API path (`/social/chat`, `/tasks/approvals`), a chat or
///   approval icon, a control labelled 'Open chat' or one that asks for or
///   gives an approval ('Approve', 'Send for approval', 'Request approval'),
///   or a label of its own that starts with one of those words. A state the
///   server reports on a row, even a list tile's ('Waiting for approval',
///   'Approved'), is not a control.
///
/// Neither module has a route or a file yet, so today this passes on nothing
/// and pins the rule for when they land. Shared files (the team kit, the ESS
/// models, whose staff profile has its own 'likes') are not the module's and
/// are scanned for (a) only. One shared file holds a multipart body that is
/// not the modules': the staff member's own profile photo upload in
/// lib/data/datasources/me_remote_data_source.dart, which a task or social
/// screen reaches when it reads the viewer's profile through MeRepository.
/// It is allowed for (a), with that reason ([_reachedUploadAllowed]); the
/// module still may not call it (`uploadPhoto` is a name that uploads).
void main() {
  group('the guard catches', () {
    test('(a) upload, capture and posting packages', () {
      expect(
        _flagged('''
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import "package:camera/camera.dart";
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
'''),
        {
          'import package:file_picker (upload or capture)',
          'import package:image_picker (upload or capture)',
          'import package:camera (upload or capture)',
          'import package:video_player (upload or capture)',
          'import package:share_plus (upload or capture)',
        },
      );
    });

    test('(a) a multipart body', () {
      expect(
        _flagged('''
Future<void> send(Dio dio, String path) => dio.post('/x',
    data: FormData.fromMap({'file': MultipartFile.fromFileSync(path)}));
'''),
        {
          'name FormData (upload or capture)',
          'name MultipartFile (upload or capture)',
        },
      );
    });

    test("(a) a module's own file that uploads", () {
      expect(
        _flagged('''
final done = me.uploadPhoto(bytes, name);
class UploadSheet extends StatelessWidget {}
'''),
        {
          'name uploadPhoto (upload or capture)',
          'name UploadSheet (upload or capture)',
        },
      );
    });

    test('(b) performance-number fields and JSON keys', () {
      expect(
        _flagged(r'''
class PostStats {
  const PostStats(this.views, this.likesCount, this.ctr);
  final int views;
  final int likesCount;
  final double ctr;
  factory PostStats.fromJson(Map<String, dynamic> j) =>
      PostStats(j['views'] as int, j['likes_count'] as int, j['ctr'] as double);
}
final watch = json['watch_time'];
const keys = ['followers', 'engagement_rate', 'impressions'];
final text = Text('$playCount plays');
final int totalShares = 0;
final int followersGained = 0;
'''),
        {
          'name views (performance number)',
          'name likesCount (performance number)',
          'name ctr (performance number)',
          'key views (performance number)',
          'key likes_count (performance number)',
          'key ctr (performance number)',
          'key watch_time (performance number)',
          'key followers (performance number)',
          'key engagement_rate (performance number)',
          'key impressions (performance number)',
          'name playCount (performance number)',
          'name totalShares (performance number)',
          'name followersGained (performance number)',
        },
      );
    });

    test('(c) approval, chat and scorecard screens and routes', () {
      // Sample paths for the self-test only; the modules' real paths come
      // from their server when they are built.
      expect(
        _flagged('''
class ApprovalQueueScreen extends StatelessWidget {}
class ChatBloc {}
class EditorScorecardTab extends StatelessWidget {}
final routes = [
  GoRoute(path: '/social/chat', builder: (_, __) => const SizedBox()),
  GoRoute(path: '/tasks/approvals', builder: (_, __) => const SizedBox()),
];
const scores = '/v1/social/editor-scorecard';
final icon = Icon(Icons.chat_bubble_outline);
'''),
        {
          'name ApprovalQueueScreen (approval)',
          'name ChatBloc (chat)',
          'name EditorScorecardTab (scorecard)',
          'path /social/chat (chat)',
          'path /tasks/approvals (approval)',
          'path /v1/social/editor-scorecard (scorecard)',
          'icon Icons.chat_bubble_outline (chat)',
        },
      );
    });

    test('(c) approval, chat and scorecard controls and labels', () {
      expect(
        _flagged('''
final approve = FilledButton(onPressed: null, child: Text('Approve'));
final send = TextButton(onPressed: null, child: Text('Send for approval'));
final ask = ListTile(title: Text('Request approval'), onTap: null);
final chat = ListTile(title: Text('Open chat'), onTap: null);
final card = ListTile(title: Text('Open the editor scorecard'), onTap: null);
const _label = 'Chat with the editor';
const _tab = 'Scorecard';
'''),
        {
          'label Approve (approval)',
          'label Send for approval (approval)',
          'label Request approval (approval)',
          'label Open chat (chat)',
          'label Open the editor scorecard (scorecard)',
          'label Chat with the editor (chat)',
          'label Scorecard (scorecard)',
        },
      );
    });

    test('(c) a file named for one', () {
      const files = {
        'lib/features/social/chat_screen.dart': 'chat',
        'lib/features/tasks/approval_sheet.dart': 'approval',
        'lib/features/tasks/editor_scorecard_tab.dart': 'scorecard',
      };
      for (final MapEntry(key: file, value: rule) in files.entries) {
        expect(_flagged('', file: file), {'file $file ($rule)'});
      }
    });

    test('a route path under the modules', () {
      expect(_routeHits('/social/chat').map((h) => h.short),
          ['route /social/chat (chat)']);
      expect(_routeHits('/tasks/:id/approve').map((h) => h.short),
          ['route /tasks/:id/approve (approval)']);
    });
  });

  group('the guard allows', () {
    test('a task list and its own states', () {
      expect(
        _flagged(r'''
class TaskListScreen extends StatelessWidget {}
class TaskTile extends StatelessWidget {}
final route = GoRoute(path: '/tasks/:id', builder: (_, __) => const SizedBox());
final title = Text('Due today');
final row = ListTile(
    title: Text(task.title), subtitle: Text('Waiting for approval'), onTap: null);
final sent = ListTile(title: Text('Sent for approval on 3 Nov'), onTap: null);
final waiting = TeamPill(label: 'Pending approval', tone: TeamPillTone.warning);
final pill = TeamPill(label: 'Approved', tone: TeamPillTone.success);
final done = FilledButton(onPressed: null, child: Text('Mark done'));
final due = json['due_date'];
final status = json['status'];
const error = 'Could not reach the server. Try again.';
final list = ListView.builder(itemCount: 0, itemBuilder: (_, __) => null);
final pages = PageView(children: const []);
final prefs = SharedPreferences.getInstance();
''', file: 'lib/features/tasks/task_list_screen.dart'),
        isEmpty,
      );
    });

    test('names that are not a performance number', () {
      expect(
        _flagged('''
class TasksHome extends StatefulWidget {}
class _TasksHomeState extends State<TasksHome> {
  final _views = <Widget>[const TaskListView(), const TaskBoardView()];
  int pendingSaves = 0;
  Widget build(BuildContext context) =>
      IndexedStack(index: _tab, children: _views);
}
final queued = json['pending_saves'];
''', file: 'lib/features/tasks/tasks_home.dart'),
        isEmpty,
      );
    });

    test("the profile photo upload a module reaches through MeRepository", () {
      const upload = '''
Future<void> uploadPhoto(List<int> bytes) => _dio.post('/me/photo',
    data: FormData.fromMap({'photo': MultipartFile.fromBytes(bytes)}));
''';
      expect(
          _reachedHits(
              'lib/data/datasources/me_remote_data_source.dart', upload),
          isEmpty);
      // Anywhere else the same body is caught.
      expect(
          _reachedHits(
                  'lib/data/datasources/ess_remote_data_source.dart', upload)
              .map((h) => h.short),
          [
            'name FormData (upload or capture)',
            'name MultipartFile (upload or capture)'
          ]);
    });

    test('comments', () {
      expect(
        _flagged('''
// No image_picker, no 'Approve' button, no chat (#54 item 13).
/// Views and likes stay on the social platforms.
/* import 'package:camera/camera.dart'; /* nested */ ChatScreen */
final a = 1;
'''),
        isEmpty,
      );
    });

    test("a shared file is not the module's own", () {
      // A social screen imports its bloc, the team kit and the ESS models;
      // the bloc imports its repository, which imports its data source. The
      // profile screen imports the kit and the ESS models too, and the
      // injection file (wiring) imports the repository and data source.
      const screen = 'lib/features/social/feed_screen.dart';
      const bloc = 'lib/features/social/bloc/feed_bloc.dart';
      const repository = 'lib/data/repositories/social_repository.dart';
      const source = 'lib/data/datasources/social_remote_data_source.dart';
      const kit = 'lib/widgets/team_kit.dart';
      const models = 'lib/domain/ess_models.dart';
      final graph = {
        screen: {bloc, kit, models},
        bloc: {repository},
        repository: {source},
        source: <String>{},
        kit: <String>{},
        models: <String>{},
        'lib/features/me/profile_screen.dart': {kit, models},
        'lib/injection.dart': {repository, source, screen},
      };
      expect(moduleOwnedFiles({screen}, graph: graph),
          {screen, bloc, repository, source});
    });
  });

  group('the app', () {
    test('the scan reads the app', () {
      final sources = libSources();
      // An empty or wrong folder must fail here, not pass the guard below.
      expect(sources.length, greaterThan(50));
      final router = lex(sources['lib/router/app_router.dart']!);
      expect(router.strings.map((s) => s.text),
          containsAll(['/home', '/approvals', '/me/profile']));
      expect(TeamModule.tasks.routePrefix, '/tasks');
      expect(TeamModule.social.routePrefix, '/social');
    });

    test('each shared file allowed an upload still holds one', () {
      for (final file in _reachedUploadAllowed.keys) {
        final source = libSources()[file];
        expect(source, isNotNull, reason: 'stale entry: $file');
        expect(_multipart.hasMatch(lex(source!).masked), isTrue,
            reason: '$file no longer uploads: drop its entry');
      }
    });

    test("the app's shared files are not owned by a screen that imports them",
        () {
      final owned = moduleOwnedFiles({'lib/features/wall/wall_screen.dart'});
      expect(owned, contains('lib/features/wall/wall_screen.dart'));
      expect(owned, isNot(contains('lib/widgets/team_kit.dart')));
      expect(owned, isNot(contains('lib/domain/ess_models.dart')));
    });

    testWidgets(
        'tasks and social have no upload, performance number, approval, '
        'chat or scorecard', (tester) async {
      final routes =
          await moduleRouteFiles(tester, {TeamModule.tasks, TeamModule.social});
      final own = moduleOwnedFiles({
        ...appFilesUnder('lib/features/tasks'),
        ...appFilesUnder('lib/features/social'),
        ...routes.values,
      });
      final reached = {for (final file in own) ...withImports(file)};
      String read(String file) => File(file).readAsStringSync();
      final hits = [
        for (final path in routes.keys) ..._routeHits(path),
        for (final file in own) ..._ownHits(file, read(file)),
        for (final file in reached) ..._reachedHits(file, read(file)),
      ];
      expect(
        hits,
        isEmpty,
        reason: 'team_app#54 item 13: the tasks and social modules have no '
            'upload, capture or posting, no performance numbers, and no '
            'approval, chat or editor scorecard. Found:\n  '
            '${hits.join('\n  ')}\n'
            'If one of these is something else, rename it or narrow the rule '
            'in this test, with the reason, in the same pull request.',
      );
    });
  });
}

/// One place that breaks #54 item 13.
class _Hit {
  const _Hit(this.file, this.line, this.kind, this.text, this.rule);

  final String file;
  final int line; // 0 for the file's own name, or a route
  final String kind; // file, route, import, name, key, path, icon or label
  final String text;
  final String rule;

  String get short => '$kind $text ($rule)';

  @override
  String toString() =>
      '${line > 0 ? '$file:$line' : file}  $kind "$text"  ($rule)';
}

/// (a) Packages that upload, capture or post.
const _uploadPackages = [
  'file_picker',
  'image_picker',
  'camera',
  'video_player',
  'share_plus',
];

/// (a) A multipart body.
final _multipart = RegExp(r'\b(MultipartFile|MultipartRequest|FormData)\b');

/// (a) Shared files a module may reach although they hold a multipart body,
/// each with why. Their upload is not the module's: a module's own file that
/// calls it is still caught ([_uploadName]).
const _reachedUploadAllowed = {
  'lib/data/datasources/me_remote_data_source.dart':
      "The staff member's own profile photo (POST /api/me/photo), sent from "
          'the Me screen. A task or social screen reaches it when it reads '
          "the viewer's profile through MeRepository.",
};

/// (a) The words of a name that uploads, in a module's own file.
final _uploadName = RegExp(r'\b(upload|uploads|uploading|uploader)\b');

/// (b) Performance words that are one wherever they stand in a name or key.
final _performanceAnywhere =
    RegExp(r'\b(impressions|engagements?|followers|ctr)\b|'
        r'\bwatch (time|hours|minutes|seconds)\b');

/// (b) Performance words that are one alone ('views', 'likes')...
final _performanceAlone = RegExp(r'^(views|reach|likes|plays|saves|shares)$');

/// ...or with a count, rate or total ('likes count', 'view rate', 'total
/// plays'), but not after another word ('pending saves').
final _performanceCounted =
    RegExp(r'\b(views?|reach|likes?|plays?|saves?|shares?|follower|impression) '
        r'(counts?|rates?|totals?)\b|'
        r'\b(total|average|avg) (views|reach|likes|plays|saves|shares)\b');

/// (b) Whether [words], a name's or a key's, are a performance number. A
/// [private] name of the word alone (`_views`) is not: a screen keeps it
/// for itself, and a number from the server comes in through a key and a
/// public field, which are caught.
bool _isPerformance(String words, {bool private = false}) =>
    _performanceAnywhere.hasMatch(words) ||
    _performanceCounted.hasMatch(words) ||
    (!private && _performanceAlone.hasMatch(words));

/// (c) Approval, chat and scorecard words: in a type, a path or a file name,
/// and on a control's label. 'Approved', a state the server reports, is not
/// a control.
final _offScope = <String, RegExp>{
  'approval': RegExp(
      r'\b(approve|approves|approving|approval|approvals|approver|approvers)\b'),
  'chat': RegExp(r'\b(chat|chats|chatting)\b'),
  'scorecard': RegExp(r'\b(scorecards?|score cards?)\b'),
};

/// (c) A chat or approval icon (Material or Cupertino).
final _offScopeIcon = RegExp(r'Icons\.(\w*_)?(chat|approval)\w*');

/// The first (c) rule [words] break, or null.
String? _offScopeRule(String words) {
  for (final MapEntry(key: rule, value: re) in _offScope.entries) {
    if (re.hasMatch(words)) return rule;
  }
  return null;
}

/// (c) A label that starts with an approval, chat or scorecard word.
final _offScopeStart = RegExp(
    r'^(approve|approval|approvals|chat|chats|scorecards?|score cards?)\b');

/// (c) A control's label that gives or asks for an approval: 'Approve',
/// 'Approve all', 'Send for approval', 'Submit to your manager for
/// approval', 'Request approval'. On a control, an approval word is caught
/// only so: a row's state ('Waiting for approval') is not an action.
final _approvalAction = RegExp(r'^(approve|approves|approving)\b|'
    r'^(re)?(send|submit|request|ask|seek|get|forward)\b(\s\w+){0,4}\s'
    r'(approval|approvals|approver|approvers)\b');

/// (c) for a route path under the modules.
List<_Hit> _routeHits(String path) => [
      if (_offScopeRule(nameWords(path)) case final rule?)
        _Hit(path, 0, 'route', path, rule),
    ];

/// (a) for a file the module's files reach: its packages and multipart body.
List<_Hit> _reachedHits(String file, String source) {
  final lexed = lex(source);
  return [
    for (final package in _uploadPackages)
      for (final quote in ["'", '"'])
        for (final m in RegExp(RegExp.escape('${quote}package:$package/'))
            .allMatches(lexed.code))
          _Hit(file, lineOf(lexed.code, m.start), 'import', 'package:$package',
              'upload or capture'),
    if (!_reachedUploadAllowed.containsKey(file))
      for (final m in _multipart.allMatches(lexed.masked))
        _Hit(file, lineOf(lexed.code, m.start), 'name', m[0]!,
            'upload or capture'),
  ];
}

/// (b) and (c) for one of the module's own files.
List<_Hit> _ownHits(String file, String source) {
  final lexed = lex(source);
  final controls = controlsIn(lexed);
  final hits = <_Hit>[];
  if (_offScopeRule(nameWords(file)) case final rule?) {
    hits.add(_Hit(file, 0, 'file', file, rule));
  }
  final seen = <String>{};
  for (final (:at, :name) in namesIn(lexed)) {
    final line = lineOf(lexed.code, at);
    if (!seen.add('$line $name')) continue;
    final words = nameWords(name);
    if (_isPerformance(words, private: name.startsWith('_'))) {
      hits.add(_Hit(file, line, 'name', name, 'performance number'));
    }
    if (_uploadName.hasMatch(words)) {
      hits.add(_Hit(file, line, 'name', name, 'upload or capture'));
    }
    if (RegExp(r'^_?[A-Z]').hasMatch(name) && !_multipart.hasMatch(name)) {
      if (_offScopeRule(words) case final rule?) {
        hits.add(_Hit(file, line, 'name', name, rule));
      }
    }
  }
  for (final m in _offScopeIcon.allMatches(lexed.masked)) {
    hits.add(_Hit(file, lineOf(lexed.code, m.start), 'icon', m[0]!,
        _offScopeRule(nameWords(m[0]!))!));
  }
  for (final (:at, :text) in lexed.strings) {
    final line = lineOf(lexed.code, at);
    if (text.trim().isEmpty || text.startsWith('package:')) continue;
    if (isLabel(text)) {
      final words = labelWords(text);
      final rule = _offScopeRule(words);
      final onControl = controlAround(controls, at) != null &&
          (rule != 'approval' || _approvalAction.hasMatch(words));
      if (rule != null && (onControl || _offScopeStart.hasMatch(words))) {
        hits.add(_Hit(file, line, 'label', text, rule));
      }
    } else if (text.contains('/')) {
      if (_offScopeRule(nameWords(text)) case final rule?) {
        hits.add(_Hit(file, line, 'path', text, rule));
      }
    } else if (_isPerformance(nameWords(text))) {
      hits.add(_Hit(file, line, 'key', text, 'performance number'));
    }
  }
  return hits;
}

/// Every hit in [source], read as one of the module's own files at [file],
/// as 'kind text (rule)', for the self-tests.
Set<String> _flagged(String source,
        {String file = 'lib/features/social/sample.dart'}) =>
    {
      ..._reachedHits(file, source).map((h) => h.short),
      ..._ownHits(file, source).map((h) => h.short),
    };

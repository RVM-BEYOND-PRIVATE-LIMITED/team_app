import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/router/module_routes.dart';

import 'support/source_scan.dart';

/// team_app#58 item 10: staff do not post or comment in the community from
/// the moderation module, and there are no private messages. Staff review
/// reports, hide or restore, warn, and read the moderation log; the staff
/// side of Scheduler_Backend#186 has nothing to compose.
///
/// The test reads the module's files with dart:io. Comments are skipped;
/// everything else is checked:
/// * file and folder names, e.g. features/moderation/compose_sheet.dart;
/// * names in the code (screens, widgets, blocs, methods, fields), e.g.
///   CreatePostScreen, CommentComposer, CommentReplySheet,
///   DirectMessageSheet, ChatScreen, MessagesTab, sendMessage;
/// * routes and API paths: each route the router has at or under
///   `TeamModule.moderation` (`/moderation`), and each string with a `/`,
///   e.g. '/moderation/compose', '/moderation/messages', '/messages',
///   '/chat', a group's posts ('/v1/community/groups/:id/posts') and a post's
///   comments ('/posts/:id/comments');
/// * labels: 'Write a post', 'New post', 'Post', 'Comment', 'Add a comment',
///   'Reply', 'Message', 'Send message'.
///
/// The module's files are every Dart file under lib/features/moderation/,
/// the file that declares each /moderation route's screen, and the files only
/// they import (`moduleOwnedFiles`, test/support/source_scan.dart).
/// lib/features/wall/ is never scanned: the staff Wall's post sheet and its
/// own moderation screen are a different, HR-only module (#58: "Do not mix
/// the two queues").
///
/// Allowed on purpose: 'Restore', 'Keep hidden', 'Hide', 'Warn',
/// 'Moderation log', and a reported post's or comment's own text, read only.
///
/// No moderation file or route exists yet, so today this passes, and it
/// catches the first compose or message control #58 adds.
void main() {
  group('the guard catches', () {
    test('a create-post screen, route and control', () {
      expect(
        _flagged(r"""
class CreatePostScreen extends StatelessWidget {}
final route = GoRoute(path: '/moderation/compose', builder: (_, __) => const CreatePostScreen());
final title = Text('Write a post');
final fab = FloatingActionButton.extended(onPressed: null, label: Text('New post'));
final send = FilledButton(onPressed: null, child: Text('Post'));
"""),
        {
          'name CreatePostScreen (post or comment)',
          'path /moderation/compose (post or comment)',
          'label Write a post (post or comment)',
          'label New post (post or comment)',
          'label Post (post or comment)',
        },
      );
    });

    test('a comment composer and the posting endpoints', () {
      expect(
        _flagged(r"""
class CommentComposer {}
class CommentReplySheet {}
const groupPosts = '/v1/community/groups/:id/posts';
const postComments = '/posts/:id/comments';
final add = TextButton(onPressed: null, child: Text('Add a comment'));
final reply = Text('Reply');
final comment = Text('Comment');
Future<void> f() => repository.addComment(postId, text);
"""),
        {
          'name CommentComposer (post or comment)',
          'name CommentReplySheet (post or comment)',
          'path /v1/community/groups/:id/posts (post or comment)',
          'path /posts/:id/comments (post or comment)',
          'label Add a comment (post or comment)',
          'label Reply (post or comment)',
          'label Comment (post or comment)',
          'name addComment (post or comment)',
        },
      );
    });

    test('a private message or chat', () {
      expect(
        _flagged(r"""
class DirectMessageSheet {}
class ChatScreen {}
class MessagesTab {}
const paths = ['/moderation/messages', '/messages', '/chat'];
final send = FilledButton(onPressed: null, child: Text('Send message'));
final message = Text('Message');
final author = Text('Message the author');
void open() => sendMessage(authorId);
"""),
        {
          'name DirectMessageSheet (private message)',
          'name ChatScreen (private message)',
          'name MessagesTab (private message)',
          'path /moderation/messages (private message)',
          'path /messages (private message)',
          'path /chat (private message)',
          'label Send message (private message)',
          'label Message (private message)',
          'label Message the author (private message)',
          'name sendMessage (private message)',
        },
      );
    });

    test('names inside an interpolation', () {
      expect(
        _flagged(r"""
void open(BuildContext context) => context.go('/moderation/$chatId');
"""),
        {
          'name chatId (private message)',
          r'path /moderation/$chatId (private message)',
        },
      );
    });

    test('a file or folder named after them', () {
      const files = {
        'lib/features/moderation/compose_sheet.dart': 'post or comment',
        'lib/features/moderation/comment_sheet.dart': 'post or comment',
        'lib/features/moderation/chat/inbox_screen.dart': 'private message',
        'lib/features/moderation/direct_message_tile.dart': 'private message',
      };
      for (final MapEntry(key: file, value: rule) in files.entries) {
        expect(_flagged('', file: file), {'file $file ($rule)'});
      }
    });

    test('a route under /moderation', () {
      expect(_routeHits('/moderation/compose').map((h) => h.short),
          ['route /moderation/compose (post or comment)']);
      expect(_routeHits('/moderation/messages/:id').map((h) => h.short),
          ['route /moderation/messages/:id (private message)']);
    });
  });

  group('the guard allows', () {
    test('the moderation actions and the log', () {
      // Sample paths for the self-test only; the module's real paths come
      // from Scheduler_Backend#186 when it is built.
      expect(
        _flagged(r"""
class ModerationQueueScreen extends StatelessWidget {}
class ReportTile extends StatelessWidget {}
class WarnSheet extends StatelessWidget {}
const routes = ['/moderation', '/moderation/reports/:id', '/moderation/log'];
final actions = [
  FilledButton(onPressed: null, child: Text('Restore')),
  OutlinedButton(onPressed: null, child: Text('Keep hidden')),
  TextButton(onPressed: null, child: Text('Hide')),
  TextButton(onPressed: null, child: Text('Warn')),
];
final log = ListTile(title: Text('Moderation log'), onTap: null);
Future<void> hide(String postId) => _dio.post('/moderation/reports/$postId/hide');
Future<void> restore(String commentId) =>
    _dio.post('/moderation/comments/$commentId/restore');
const moderators = '/moderation/moderators';
""", file: 'lib/features/moderation/moderation_queue_screen.dart'),
        isEmpty,
      );
    });

    test("a reported post's text and its states, read only", () {
      expect(
        _flagged(r"""
final title = Text('Reported post');
final body = Text(report.postText ?? 'The post was removed.');
final states = ['Post hidden', 'Comment hidden', 'Hidden by a moderator'];
final tabs = [Tab(text: 'Posts'), Tab(text: 'Comments')];
final count = Text('Reported by ${report.count} people');
final reason = Text('Reason: ${report.reason}');
final error = Text(failure.message);
final messenger = ScaffoldMessenger.of(context);
final text = json['message'];
final warn = Text('Warn the author');
"""),
        isEmpty,
      );
    });

    test("comments, and never the staff Wall's files", () {
      expect(
        _flagged(r"""
// No 'Write a post' or 'Message' button here: staff only moderate (#58).
/// [CreatePostSheet] is the staff Wall's, not this module's.
/* class ChatScreen, '/messages' /* nested */ still a comment */
final a = 1;
"""),
        isEmpty,
      );
      expect(_inScope('lib/features/wall/create_post_sheet.dart'), isFalse);
      expect(
          _inScope('lib/features/wall/wall_moderation_screen.dart'), isFalse);
      expect(_inScope('lib/features/moderation/queue_screen.dart'), isTrue);
    });
  });

  group('the app', () {
    test('the scan reads lib/router/app_router.dart', () {
      final sources = libSources();
      // An empty or wrong folder must fail here, not pass the guard below.
      expect(sources.length, greaterThan(50));
      final router = lex(sources['lib/router/app_router.dart']!);
      expect(router.strings.map((s) => s.text),
          containsAll(['/home', '/approvals', '/wall/post/:id']));
      expect(router.code, contains('GoRoute('));
      expect(TeamModule.moderation.routePrefix, '/moderation');
    });

    testWidgets('the router walk sees the app\'s routes', (tester) async {
      final paths = (await appRoutes(tester)).map((r) => r.path);
      expect(paths, containsAll(['/home', '/wall/post/:id']));
    });

    testWidgets(
        'has no post, comment or private-message route, screen or control '
        'under moderation', (tester) async {
      final routes = await moduleRouteFiles(tester, {TeamModule.moderation});
      final own = moduleOwnedFiles({
        ...appFilesUnder('lib/features/moderation'),
        ...routes.values,
      }).where(_inScope);
      final hits = [
        for (final path in routes.keys) ..._routeHits(path),
        for (final file in own) ..._scan(file, File(file).readAsStringSync()),
      ];
      expect(
        hits,
        isEmpty,
        reason: 'team_app#58 item 10: staff do not post or comment in the '
            'community from the moderation module, and there are no private '
            'messages (Scheduler_Backend#186 has nothing to compose). '
            'Found:\n  ${hits.join('\n  ')}\n'
            'If one of these is something else (a reported post\'s own '
            'text, say), rename it or narrow the rule in this test, with the '
            'reason, in the same pull request.',
      );
    });
  });
}

/// One place that adds posting, commenting or messaging to moderation.
class _Hit {
  const _Hit(this.file, this.line, this.kind, this.text, this.rule);

  final String file;
  final int line; // 0 for the file's own name, or a route
  final String kind; // file, route, name, path or label
  final String text;
  final String rule;

  String get short => '$kind $text ($rule)';

  @override
  String toString() =>
      '${line > 0 ? '$file:$line' : file}  $kind "$text"  ($rule)';
}

/// The staff Wall (HR-only) is a different module: never scanned here.
bool _inScope(String file) => !file.startsWith('lib/features/wall/');

const _post = 'post or comment';
const _message = 'private message';

/// Rules for the words of any name: 'create post', 'add comment', 'send
/// message', a composer, a comment sheet, a direct message, a chat.
final _nameRules = <String, RegExp>{
  _post: RegExp(
      r'\b(create|new|write|compose|add|publish|start|leave) (posts?|comments?|repl(y|ies))\b|'
      r'\bcomposer\b|^comment\b.*\bsheet\b'),
  _message:
      RegExp(r'\b(send|new|write|compose|start) (messages?|chats?|dms?)\b|'
          r'\b(direct|private) messages?\b|\bchats?\b|\bchatting\b'),
};

/// More rules for a type's name ('MessagesTab', 'ReplySheet').
final _typeRules = <String, RegExp>{
  _post: RegExp(r'^(reply|replies)\b'),
  _message: RegExp(r'^messages?\b'),
};

/// Rules for the words of a route or API path.
final _pathRules = <String, RegExp>{
  _post: RegExp(r'\b(compose|composer)\b|\b(posts|comments|replies|reply)$|'
      r'\b(new|create) (posts?|comments?)\b|\b(posts?|comments?) (new|create)\b'),
  _message: RegExp(
      r'\b(messages?|chats?|dms?|conversations?)\b|\bdirect messages?\b'),
};

/// Rules for a label's words.
final _labelRules = <String, RegExp>{
  _post: RegExp(r'^(post|comment|reply|compose|publish)$|'
      r'\b(write|new|create|add|compose|publish|start|leave|send|post) '
      r'(a |an |the |new |your )?(posts?|comments?|repl(y|ies))\b|'
      r'\breply to\b'),
  _message: RegExp(r'^(message|messages|chat|chats)$|'
      r'\b(write|new|send|start|compose) (a |an |the |new |your )?'
      r'(messages?|chats?|dms?)\b|'
      r'\b(direct|private) messages?\b|'
      r'\bmessage (the )?(author|poster|reporter|student|member|user|them)\b|'
      r'\bchats?\b|\bdms?\b'),
};

String? _rule(Map<String, RegExp> rules, String words) {
  for (final MapEntry(key: rule, value: re) in rules.entries) {
    if (re.hasMatch(words)) return rule;
  }
  return null;
}

/// A route under /moderation.
List<_Hit> _routeHits(String path) => [
      if (_rule(_pathRules, nameWords(path)) case final rule?)
        _Hit(path, 0, 'route', path, rule),
    ];

/// Every hit in one file: its own name, the names in its code and its strings.
List<_Hit> _scan(String file, String source) {
  final hits = <_Hit>[];
  final base = file.split('/').last.replaceAll('.dart', '');
  if (_rule(_nameRules, nameWords(base)) ??
          _rule(_pathRules, nameWords(file.replaceAll('.dart', '')))
      case final rule?) {
    hits.add(_Hit(file, 0, 'file', file, rule));
  }

  final lexed = lex(source);
  final seen = <String>{};
  for (final (:at, :name) in namesIn(lexed)) {
    final line = lineOf(lexed.code, at);
    if (!seen.add('$line $name')) continue;
    final words = nameWords(name);
    final type = RegExp(r'^_?[A-Z]').hasMatch(name);
    if (_rule(_nameRules, words) ?? (type ? _rule(_typeRules, words) : null)
        case final rule?) {
      hits.add(_Hit(file, line, 'name', name, rule));
    }
  }

  for (final (:at, :text) in lexed.strings) {
    final line = lineOf(lexed.code, at);
    if (text.trim().isEmpty || text.startsWith('package:')) continue;
    if (isLabel(text)) {
      if (_rule(_labelRules, labelWords(text)) case final rule?) {
        hits.add(_Hit(file, line, 'label', text, rule));
      }
    } else if (text.contains('/')) {
      if (_rule(_pathRules, nameWords(text)) case final rule?) {
        hits.add(_Hit(file, line, 'path', text, rule));
      }
    }
  }
  return hits;
}

/// The hits in [source] as 'kind text (rule)', for the self-tests.
Set<String> _flagged(String source,
        {String file = 'lib/features/moderation/sample.dart'}) =>
    _scan(file, source).map((h) => h.short).toSet();

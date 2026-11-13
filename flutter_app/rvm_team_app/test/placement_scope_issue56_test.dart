import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// team_app#56 item 13 and check 10: the Team app has no job, campus drive,
/// job approval, post-for-a-company or waiver route, screen or control. They
/// stay on the placement team's Campus screens (RVMBeyond_jobportal#159).
///
/// The test reads every Dart file under lib/ with dart:io. Comments are
/// skipped; everything else is checked:
/// * file and folder names, e.g. features/placement/jobs_screen.dart;
/// * names in the code (screens, widgets, blocs, models, methods, fields),
///   e.g. JobsScreen, CampusDriveTile, JobApprovalBloc, WaiverSheet,
///   PostForACompanyScreen, and the JobPortal types JobsRepository and
///   JobSummary;
/// * strings without spaces (routes, navigation targets, API paths, imports,
///   JSON keys), e.g. '/placement/jobs', '/placement/job-approvals',
///   '/drives', '/waivers', 'post-for-a-company';
/// * labels, in the words Campus uses for these screens: 'Jobs',
///   'Post a job', 'Approve job', 'Campus drives', 'Drive requests',
///   'Post for a company', 'Waivers in force',
///   'RVM applicants free for this company'.
///
/// Allowed on purpose: the employee's own job title and job role from the HR
/// record (the profile's 'Job' section), the JobPortal client's own names in
/// core_network and core_auth (jobPortal, signOutJobPortal), an on-duty reason
/// such as 'College drive at the Pune centre' (the ESS contract's example),
/// and what #56 itself plans: company follow-ups and proof checks under
/// /placement, the student desk under /desk.
void main() {
  group('the guard catches', () {
    test('a job route, screen and control', () {
      expect(
        _flagged(r"""
class JobsScreen extends StatelessWidget {}
final route = GoRoute(path: '/placement/jobs', builder: (_, __) => const JobsScreen());
final tab = Text('Jobs');
final button = TextButton(onPressed: null, child: Text('Post a job'));
"""),
        {
          'name JobsScreen (job)',
          'path /placement/jobs (job)',
          'label Jobs (job)',
          'label Post a job (job)',
        },
      );
    });

    test('a campus drive route, screen and control', () {
      expect(
        _flagged(r"""
class CampusDrivesTab extends StatelessWidget {}
void open(BuildContext context) => context.go('/placement/drives');
final title = Text('Campus drives');
final queue = Text('Drive requests');
final tile = Text('Drives');
"""),
        {
          'name CampusDrivesTab (campus drive)',
          'path /placement/drives (campus drive)',
          'label Campus drives (campus drive)',
          'label Drive requests (campus drive)',
          'label Drives (campus drive)',
        },
      );
    });

    test('a job approval route, screen and control', () {
      expect(
        _flagged(r"""
class JobApprovalBloc {}
final route = GoRoute(path: '/placement/job-approvals', builder: (_, __) => const SizedBox());
final title = Text('Job approvals');
final approve = FilledButton(onPressed: null, child: Text('Approve job'));
"""),
        {
          'name JobApprovalBloc (job approval)',
          'path /placement/job-approvals (job approval)',
          'label Job approvals (job approval)',
          'label Approve job (job approval)',
        },
      );
    });

    test('a post-for-a-company route, screen and control', () {
      expect(
        _flagged(r"""
class PostForACompanyScreen extends StatelessWidget {}
final route = GoRoute(path: '/placement/post-for-a-company', builder: (_, __) => const PostForACompanyScreen());
final tile = Text('Post for a company');
final button = Text('Post a job for the company');
"""),
        {
          'name PostForACompanyScreen (post for a company)',
          'path /placement/post-for-a-company (post for a company)',
          'label Post for a company (post for a company)',
          'label Post a job for the company (post for a company)',
        },
      );
    });

    test('a waiver route, screen and control', () {
      expect(
        _flagged(r"""
class WaiverSheet extends StatelessWidget {}
final route = GoRoute(path: '/placement/waivers', builder: (_, __) => const WaiverSheet());
final list = Text('Waivers in force');
final toggle = SwitchListTile(value: false, onChanged: null, title: Text('RVM applicants free for this company'));
"""),
        {
          'name WaiverSheet (waiver)',
          'path /placement/waivers (waiver)',
          'label Waivers in force (waiver)',
          'label RVM applicants free for this company (waiver)',
        },
      );
    });

    test('the JobPortal job data and endpoints', () {
      expect(
        _flagged(r"""
import 'package:data/data.dart';

class Sample {
  Sample(this.repo);
  final JobsRepository repo;
  final List<JobSummary> open = const [];
}
const saved = '/candidates/saved-jobs';
"""),
        {
          'name JobsRepository (job)',
          'name JobSummary (job)',
          'path /candidates/saved-jobs (job)',
        },
      );
    });

    test('names inside an interpolation', () {
      expect(
        _flagged(r"""
final count = Text('${jobs.length} open');
void open(BuildContext context) => context.go('/placement/$driveId');
"""),
        {'name jobs (job)', 'name driveId (campus drive)'},
      );
    });

    test('a file or folder named after them', () {
      const files = {
        'lib/features/jobs/list_screen.dart': 'job',
        'lib/features/placement/campus_drive_tile.dart': 'campus drive',
        'lib/features/placement/job_approvals_screen.dart': 'job approval',
        'lib/features/placement/post_for_a_company_screen.dart':
            'post for a company',
        'lib/features/placement/waiver_sheet.dart': 'waiver',
      };
      for (final MapEntry(key: file, value: rule) in files.entries) {
        expect(_flagged('', file: file), {'file $file ($rule)'});
      }
    });
  });

  group('the guard allows', () {
    test("the employee's own job title and role from the HR record", () {
      expect(
        _flagged(r"""
final section = _Section(title: 'Job', rows: const []);
final subtitle = Text('Summary, job and timeline');
final field = TextField(decoration: InputDecoration(labelText: 'Job title'));
const error = 'Job title is required.';
final role = Text(card.designation ?? 'Job role not recorded');
final jobTitle = json['job_title'];
final jobRole = json['jobRole'];
"""),
        isEmpty,
      );
    });

    test("comments and the JobPortal client's own names", () {
      expect(
        _flagged(r"""
// Drives the offline banner.
/// Post a job, campus drive, job approval, waiver: all stay on Campus.
/* class JobsScreen, '/placement/jobs' /* nested */ still a comment */
final dio = DioFactory.jobPortal(env: env, cookieJar: jar);
final base = env.jobPortalBaseUrl;
Future<void> signOut() => session.signOutJobPortal();
"""),
        isEmpty,
      );
    });

    test('Wall posts, leave approvals, the praise badge and on-duty reasons',
        () {
      expect(
        _flagged(r"""
class CreatePostSheet {}
final routes = [
  GoRoute(path: '/approvals', builder: (_, __) => const ApprovalsScreen()),
  GoRoute(path: '/wall/post/:id', builder: (_, __) => const SizedBox()),
];
final post = Text('Post');
const hint = 'Write something before posting.';
final badge = {'placement': Icons.rocket_launch_outlined};
const reason = 'e.g. College drive at the Pune centre';
"""),
        isEmpty,
      );
    });

    test('what #56 itself plans under /placement and /desk', () {
      expect(
        _flagged(r"""
class CompanyFollowUpsScreen {}
class VerificationTaskScreen {}
const routes = ['/placement/follow-ups', '/placement/tasks/:id', '/desk', '/desk/phone-changes', '/desk/extra-views'];
const states = ['Campus arranged', 'Walk-in arranged', 'Virtual campus arranged', 'No vacancy', 'Vacancy available'];
final labels = [
  Text('Company follow-ups'),
  Text('Approve'),
  Text('Reject'),
  Text('Selected or hired by the company'),
  Text('Offer or joining letter'),
  Text('Reward status'),
];
""", file: 'lib/features/placement/verification_task_screen.dart'),
        isEmpty,
      );
    });
  });

  group('the app', () {
    test('the scan reads the whole of lib/', () {
      final files = _libFiles();
      // An empty or wrong folder must fail here, not pass the guard below.
      expect(files.length, greaterThan(50));
      final router = _Lexer(files['lib/router/app_router.dart']!)..readCode();
      expect(router.strings.map((s) => s.$2),
          containsAll(['/home', '/approvals', '/me/profile']));
      expect(router.code.toString(), contains('GoRoute('));
    });

    test(
        'has no job, campus drive, job approval, post-for-a-company or '
        'waiver route, screen or control', () {
      final hits = [
        for (final MapEntry(key: file, value: source) in _libFiles().entries)
          ..._scan(file, source),
      ];
      expect(
        hits,
        isEmpty,
        reason: 'team_app#56 item 13: job, campus drive, job approval, '
            'post-for-a-company and waiver screens stay on the placement '
            "team's Campus screens (RVMBeyond_jobportal#159), not in the "
            'Team app. Found:\n  ${hits.join('\n  ')}\n'
            'If one of these is something else (for example the '
            "employee's own job title), rename it or narrow the rule in "
            'this test, with the reason, in the same pull request.',
      );
    });
  });
}

/// One place in lib/ that names a job, campus drive, job approval,
/// post-for-a-company or waiver thing.
class _Hit {
  const _Hit(this.file, this.line, this.kind, this.text, this.rule);

  final String file;
  final int line; // 0 for the file's own name
  final String kind; // file, name, path or label
  final String text;
  final String rule;

  String get short => '$kind $text ($rule)';

  @override
  String toString() =>
      '${line > 0 ? '$file:$line' : file}  $kind "$text"  ($rule)';
}

/// 'post for a company', 'post a job for the company', 'posting on behalf of
/// an employer': the same words in a name, a path or a label.
final _postForACompany = RegExp(
    r'\bpost(?:s|ed|ing)? (?:(?:a |an |the |new )*jobs? )?(?:for|on behalf of) (?:a |an |the |this )?(?:company|companies|employer|employers)\b');

/// Rules for the words of a name, a file or a string without spaces. Checked
/// in order; the first that matches names the hit. 'job' is allowed before
/// title, role and portal: the employee's own job title and role, and the
/// JobPortal client's names.
final _wordRules = <String, RegExp>{
  'job approval': RegExp(
      r'\bjob approvals?\b|\b(?:approv|reject|review)\w* (?:the |this |a |all |pending )?jobs?\b'),
  'post for a company': _postForACompany,
  'campus drive': RegExp(r'\bdrives?\b'),
  'waiver': RegExp(r'\bwaiv'),
  'job': RegExp(r'\bjobs\b|\bjob\b(?! (?:title|role|portal)\b)'),
};

/// Rules for labels, in the words Campus uses for these screens
/// (RVMBeyond_jobportal#159, badabhai-platform#2742). A lone 'Job', 'job
/// title' and 'College drive' (an on-duty reason) are not controls.
final _labelRules = <String, RegExp>{
  'job approval': RegExp(
      r'\bjob approvals?\b|\b(?:approve|approving|reject|rejecting|review|reviewing) (?:the |this |a |an |all |pending )?jobs?\b'),
  'post for a company': _postForACompany,
  'campus drive': RegExp(
      r'\b(?:campus|placement) drives?\b|\bdrive requests?\b|\b(?:ask|request|schedule) (?:for )?(?:a |an |the )?drive\b|^drives?$'),
  'waiver': RegExp(r'\bwaiv|\bfree for (?:this|the|a) (?:job|company)\b'),
  'job': RegExp(
      r'\bjobs\b|\bjob (?:posts?|postings?|listings?|openings?|applications?|board|fair|portal)\b|\b(?:post|posting|publish|suspend|apply for|apply to|save|unsave|create|add|new) (?:a |an |the |this |new )?job\b(?! (?:title|role)\b)'),
};

final _name = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');
final _space = RegExp(r'\s');
final _oneWord = RegExp(r'^[A-Z][a-z]*$');

/// The lower-case words of a name, path or file: 'CampusDrivesTab' gives
/// 'campus drives tab', '/placement/job-approvals' gives
/// 'placement job approvals'.
String _words(String s) => s
    .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .replaceAllMapped(RegExp(r'([A-Z])([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

/// A label as lower-case words: 'Walk-in arranged' gives 'walk in arranged'.
String _labelWords(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Every hit in one file: its own name, the names in its code and its strings.
List<_Hit> _scan(String file, String source) {
  final hits = <_Hit>[];
  void check(int line, String kind, String text, Map<String, RegExp> rules,
      String words) {
    for (final rule in rules.entries) {
      if (rule.value.hasMatch(words)) {
        hits.add(_Hit(file, line, kind, text, rule.key));
        return;
      }
    }
  }

  check(0, 'file', file, _wordRules, _words(file));

  final lexer = _Lexer(source)..readCode();
  final code = lexer.code.toString();
  final seen = <String>{};
  var line = 1;
  var at = 0;
  for (final m in _name.allMatches(code)) {
    line += '\n'.allMatches(code.substring(at, m.start)).length;
    at = m.start;
    final name = m[0]!;
    if (seen.add('$line $name')) {
      check(line, 'name', name, _wordRules, _words(name));
    }
  }

  for (final (start, text) in lexer.strings) {
    if (text.trim().isEmpty) continue;
    // A string with spaces, or one capitalised word such as 'Jobs', is a
    // label; anything else is a route, a path, an import or a key.
    if (text.contains(_space) || _oneWord.hasMatch(text)) {
      check(start, 'label', text, _labelRules, _labelWords(text));
    } else {
      check(start, 'path', text, _wordRules, _words(text));
    }
  }
  return hits;
}

/// The hits in [source] as 'kind text (rule)', for the self-tests.
Set<String> _flagged(String source,
        {String file = 'lib/features/placement/sample.dart'}) =>
    _scan(file, source).map((h) => h.short).toSet();

/// Every Dart file under the app's lib/, read with dart:io, by path.
Map<String, String> _libFiles() {
  if (!File('lib/router/app_router.dart').existsSync()) {
    fail('Run this test from flutter_app/rvm_team_app (flutter test does): '
        'it reads lib/ there, and a scan of nothing would prove nothing.');
  }
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final f in files) f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
  };
}

/// Splits Dart source into its code, with comments dropped and each string
/// literal replaced by a space, and its string literals with the line each
/// starts on. The code keeps the file's line breaks, so a name's line follows
/// from its offset. An interpolation's code goes to the code; in the string
/// it reads as '-'.
class _Lexer {
  _Lexer(this._src);

  final String _src;
  final code = StringBuffer();
  final strings = <(int, String)>[];
  var _i = 0;
  var _line = 1;

  static final _identifierChar = RegExp(r'[A-Za-z0-9_$]');
  static final _identifier = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');
  static final _letterOrDigit = RegExp(r'[A-Za-z0-9]');

  /// Reads code to the end of the file or, inside `${...}`, to the brace that
  /// closes it.
  void readCode({bool interpolation = false}) {
    var depth = 0;
    while (_i < _src.length) {
      final c = _src[_i];
      if (_src.startsWith('//', _i)) {
        while (_i < _src.length && _src[_i] != '\n') {
          _i++;
        }
        continue;
      }
      if (_src.startsWith('/*', _i)) {
        _skipBlockComment();
        continue;
      }
      final raw = c == 'r' &&
          _i + 1 < _src.length &&
          (_src[_i + 1] == "'" || _src[_i + 1] == '"') &&
          (_i == 0 || !_identifierChar.hasMatch(_src[_i - 1]));
      if (c == "'" || c == '"' || raw) {
        _readString();
        code.write(' ');
        continue;
      }
      if (interpolation && c == '{') depth++;
      if (interpolation && c == '}') {
        if (depth == 0) {
          _i++;
          return;
        }
        depth--;
      }
      if (c == '\n') _line++;
      code.write(c);
      _i++;
    }
  }

  /// Skips a block comment; Dart's nest.
  void _skipBlockComment() {
    var depth = 0;
    while (_i < _src.length) {
      if (_src.startsWith('/*', _i)) {
        depth++;
        _i += 2;
      } else if (_src.startsWith('*/', _i)) {
        depth--;
        _i += 2;
        if (depth == 0) return;
      } else {
        if (_src[_i] == '\n') {
          _line++;
          code.write('\n');
        }
        _i++;
      }
    }
  }

  void _readString() {
    final start = _line;
    final raw = _src[_i] == 'r';
    if (raw) _i++;
    final quote = _src[_i];
    final close = _src.startsWith(quote * 3, _i) ? quote * 3 : quote;
    _i += close.length;
    final text = StringBuffer();
    while (_i < _src.length && !_src.startsWith(close, _i)) {
      final c = _src[_i];
      if (c == '\n') {
        if (close.length == 1) break; // not valid Dart: stop at the line end
        _line++;
        code.write('\n');
      }
      if (!raw && c == r'\' && _i + 1 < _src.length) {
        // An escaped quote, dollar or backslash is kept; \n, \t, \u... read
        // as a space.
        final escaped = _src[_i + 1];
        text.write(_letterOrDigit.hasMatch(escaped) ? ' ' : escaped);
        _i += 2;
        continue;
      }
      if (!raw && _src.startsWith(r'${', _i)) {
        _i += 2;
        code.write(' ');
        readCode(interpolation: true);
        code.write(' ');
        text.write('-');
        continue;
      }
      final simple =
          !raw && c == r'$' ? _identifier.matchAsPrefix(_src, _i + 1) : null;
      if (simple != null) {
        code.write(' ${simple[0]} ');
        text.write('-');
        _i = simple.end;
        continue;
      }
      text.write(c);
      _i++;
    }
    if (_src.startsWith(close, _i)) _i += close.length;
    strings.add((start, text.toString()));
  }
}

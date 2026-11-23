import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/quiz_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import 'crm_shared.dart';

/// The caller's quiz of the day (#152, Scheduler_Backend #692).
class CrmQuizScreen extends StatefulWidget {
  const CrmQuizScreen({super.key});

  @override
  State<CrmQuizScreen> createState() => _CrmQuizScreenState();
}

class _CrmQuizScreenState extends State<CrmQuizScreen> {
  QuizRound? _round;
  QuizOpened? _opened;
  QuizAnswerResult? _result;
  Timer? _timer;
  int _secondsLeft = 0;
  bool _loading = true;
  bool _busy = false;
  bool _timeUp = false;
  String? _error;

  bool get _inQuestion => _opened != null && _result == null && !_timeUp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final current = await crmRepository().quizCurrentSafe();
      if (!mounted) return;
      if (current.failure != null) {
        setState(() => _error = current.failure!.message);
      } else {
        final round = current.data?.round;
        setState(() => _round = round);
        if (round != null && round.isOpen) {
          _begin(
            QuizOpened(
              roundId: round.id,
              question: round.question!,
              options: round.options,
              deadlineAt: round.deadlineAt,
              secondsLeft: round.secondsLeft ?? round.answerSeconds,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the quiz.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    final round = _round;
    if (round == null || _busy) return;
    setState(() => _busy = true);
    try {
      final opened = await crmRepository().quizOpen(
        round.id,
        idempotencyKey:
            'quiz-open-${round.id}-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      _begin(opened);
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            error is Failure ? error.message : 'Could not start the quiz.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _begin(QuizOpened opened) {
    _timer?.cancel();
    _opened = opened;
    _result = null;
    _timeUp = false;
    _secondsLeft = opened.secondsLeft.clamp(0, 600);
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    if (_secondsLeft <= 0) {
      _timer?.cancel();
      setState(() => _timeUp = true);
      return;
    }
    setState(() => _secondsLeft -= 1);
  }

  Future<void> _answer(int index) async {
    final opened = _opened;
    if (opened == null || _busy || _result != null || _timeUp) return;
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      final result = await crmRepository().quizAnswer(
        opened.roundId,
        index,
        idempotencyKey:
            'quiz-answer-${opened.roundId}-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            error is Failure ? error.message : 'Could not save the answer.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopScope(
      canPop: !_inQuestion,
      child: Scaffold(
        backgroundColor: p.canvas,
        appBar: AppBar(
          title: const Text('Quiz of the day'),
          automaticallyImplyLeading: !_inQuestion,
        ),
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const AppLoading(label: 'Looking for your quiz…');
    if (_error != null) {
      return AppError(message: _error!, onRetry: _load);
    }
    if (_result != null) {
      return _ResultView(result: _result!, onClose: () => context.pop());
    }
    if (_timeUp) {
      return _CenterCard(
        icon: Icons.timer_off_outlined,
        title: 'Time is up',
        body: 'This quiz is marked missed. It will count in your results.',
        action: 'Close',
        onAction: () => context.pop(),
      );
    }
    final opened = _opened;
    if (opened != null) {
      return ListView(
        padding: const EdgeInsets.all(RvmSpacing.md),
        children: [
          TeamCard(
            child: Row(
              children: [
                Icon(Icons.timer_outlined, color: context.palette.primary),
                const SizedBox(width: RvmSpacing.sm),
                Text(
                  _clock(_secondsLeft),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _secondsLeft <= 10
                        ? context.palette.danger
                        : context.palette.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                const Text('1 question'),
              ],
            ),
          ),
          const SizedBox(height: RvmSpacing.md),
          TeamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(opened.question,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: RvmSpacing.md),
                for (var i = 0; i < opened.options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: RvmSpacing.sm),
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _answer(i),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(
                          '${String.fromCharCode(65 + i)}. ${opened.options[i]}'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: RvmSpacing.md),
          Text(
            'The Knowledge Base is hidden until you answer.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }
    final round = _round;
    if (round == null) {
      return _CenterCard(
        icon: Icons.quiz_outlined,
        title: 'No quiz waiting',
        body: 'A quiz arrives twice a day, inside your shift.',
        action: 'Refresh',
        onAction: _load,
      );
    }
    return _CenterCard(
      icon: Icons.quiz_outlined,
      title: 'Quiz of the day',
      body:
          'One question. You have ${round.answerSeconds} seconds once you start.',
      action: 'Start',
      onAction: _start,
      busy: _busy,
    );
  }

  static String _clock(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(RvmSpacing.lg),
        child: TeamCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: context.palette.primary),
              const SizedBox(height: RvmSpacing.md),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: RvmSpacing.sm),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: RvmSpacing.lg),
              TeamPrimaryButton(
                  label: action, busy: busy, onPressed: busy ? null : onAction),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.onClose});
  final QuizAnswerResult result;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final correct = result.correct == true;
    return ListView(
      padding: const EdgeInsets.all(RvmSpacing.md),
      children: [
        TeamCard(
          child: Column(
            children: [
              Icon(
                correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 48,
                color: correct ? p.success : p.danger,
              ),
              const SizedBox(height: RvmSpacing.sm),
              Text(
                correct
                    ? 'Correct'
                    : result.status == 'missed'
                        ? 'Missed'
                        : 'Not this time',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (result.correctIndex != null)
                Text(
                    'The answer was ${String.fromCharCode(65 + result.correctIndex!)}'),
            ],
          ),
        ),
        if (result.explanation != null && result.explanation!.isNotEmpty) ...[
          const SizedBox(height: RvmSpacing.md),
          TeamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Why', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: RvmSpacing.xs),
                Text(result.explanation!),
              ],
            ),
          ),
        ],
        if (result.kbSection != null && result.kbSection!.isNotEmpty) ...[
          const SizedBox(height: RvmSpacing.md),
          TeamCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Read this section'),
              subtitle: Text(result.kbSection!),
            ),
          ),
        ],
        const SizedBox(height: RvmSpacing.lg),
        TeamPrimaryButton(label: 'Close', onPressed: onClose),
      ],
    );
  }
}

/// "My quiz" (#152 item 4): today, week, month, streak and history.
class CrmQuizMeScreen extends StatefulWidget {
  const CrmQuizMeScreen({super.key});
  @override
  State<CrmQuizMeScreen> createState() => _CrmQuizMeScreenState();
}

class _CrmQuizMeScreenState extends State<CrmQuizMeScreen> {
  QuizMe? _me;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await crmRepository().quizMe();
      if (mounted) setState(() => _me = me);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is Failure
            ? error.message
            : 'Could not load your quiz scores.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My quiz')),
      body: _loading
          ? const AppLoading()
          : _error != null
              ? AppError(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(RvmSpacing.md),
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: _Tally(label: 'Today', tally: _me!.today)),
                        const SizedBox(width: RvmSpacing.sm),
                        Expanded(
                            child:
                                _Tally(label: 'This week', tally: _me!.week)),
                        const SizedBox(width: RvmSpacing.sm),
                        Expanded(
                            child:
                                _Tally(label: 'This month', tally: _me!.month)),
                      ],
                    ),
                    const SizedBox(height: RvmSpacing.md),
                    TeamCard(
                      child: Text(
                        'Streak: ${_me!.streak} correct in a row',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: RvmSpacing.md),
                    TeamCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('History',
                              style: Theme.of(context).textTheme.titleSmall),
                          for (final item in _me!.history)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                item.correct == true
                                    ? Icons.check_circle_outline
                                    : Icons.cancel_outlined,
                                color: item.correct == true
                                    ? context.palette.success
                                    : context.palette.danger,
                              ),
                              title: Text(item.kbSection ?? 'Quiz'),
                              subtitle: Text(item.date),
                              trailing: Text(item.status),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({required this.label, required this.tally});
  final String label;
  final QuizTally tally;

  @override
  Widget build(BuildContext context) {
    return TeamCard(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: RvmSpacing.xs),
          Text('${tally.answered}/${tally.rounds}',
              style: Theme.of(context).textTheme.titleMedium),
          Text('${tally.accuracy?.toStringAsFixed(0) ?? '—'}%'),
        ],
      ),
    );
  }
}

/// Team leaders and above: today's team results (#152 item 5).
class CrmQuizResultsScreen extends StatefulWidget {
  const CrmQuizResultsScreen({super.key});
  @override
  State<CrmQuizResultsScreen> createState() => _CrmQuizResultsScreenState();
}

class _CrmQuizResultsScreenState extends State<CrmQuizResultsScreen> {
  QuizResults? _results;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 6));
    _load(from, now);
  }

  Future<void> _load(DateTime from, DateTime to) async {
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      final results =
          await crmRepository().quizResults(from: day(from), to: day(to));
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            error is Failure ? error.message : 'Could not load the results.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz results')),
      body: _loading
          ? const AppLoading()
          : _error != null
              ? AppError(
                  message: _error!,
                  onRetry: () {
                    final now = DateTime.now();
                    setState(() => _loading = true);
                    _load(now.subtract(const Duration(days: 6)), now);
                  },
                )
              : ListView(
                  padding: const EdgeInsets.all(RvmSpacing.md),
                  children: [
                    Text(
                      'Accuracy ${_results!.accuracy?.toStringAsFixed(0) ?? '—'}% · last 7 days',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: RvmSpacing.sm),
                    for (final person in _results!.people)
                      TeamCard(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(person.name),
                          subtitle: Text(
                            '${person.answered} answered · ${person.missed} missed',
                          ),
                          trailing: Text(
                            '${person.accuracy?.toStringAsFixed(0) ?? '—'}%',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// A card on the dialer's home when a round is waiting (#152 item 1).
class CrmQuizCard extends StatefulWidget {
  const CrmQuizCard({super.key, required this.hasOpenCall});

  final bool hasOpenCall;

  @override
  State<CrmQuizCard> createState() => _CrmQuizCardState();
}

class _CrmQuizCardState extends State<CrmQuizCard> {
  Timer? _poll;
  QuizRound? _round;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void didUpdateWidget(covariant CrmQuizCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasOpenCall != widget.hasOpenCall && !widget.hasOpenCall) {
      _load();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await crmRepository().quizCurrentSafe();
    if (!mounted) return;
    setState(() => _round = result.failure == null ? result.data?.round : null);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hasOpenCall) return const SizedBox.shrink();
    final round = _round;
    if (round == null) return const SizedBox.shrink();
    final p = context.palette;
    final open = round.isOpen;
    return Padding(
      padding: const EdgeInsets.only(bottom: RvmSpacing.md),
      child: TeamCard(
        color: p.cardElevated,
        borderColor: p.primary,
        onTap: () async {
          await context.push('/crm/quiz');
          _load();
        },
        child: Row(
          children: [
            Icon(Icons.quiz_outlined, color: p.primary),
            const SizedBox(width: RvmSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    open ? 'Quiz in progress' : 'Quiz of the day',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    open
                        ? 'Continue before the timer ends.'
                        : 'One question. Start when you are ready.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// "My quiz" and, for team leaders and above, the team results (#152).
class CrmQuizLinks extends StatefulWidget {
  const CrmQuizLinks({super.key});

  @override
  State<CrmQuizLinks> createState() => _CrmQuizLinksState();
}

class _CrmQuizLinksState extends State<CrmQuizLinks> {
  bool _canSeeResults = false;

  @override
  void initState() {
    super.initState();
    _loadLevel();
  }

  Future<void> _loadLevel() async {
    try {
      final me = await crmRepository().me();
      if (mounted) {
        setState(() => _canSeeResults = me.level != 'counsellor');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.quiz_outlined),
          title: const Text('My quiz'),
          subtitle: const Text('Today, this week and your streak'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/crm/quiz/me'),
        ),
        if (_canSeeResults) ...[
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.leaderboard_outlined),
            title: const Text('Quiz results'),
            subtitle: const Text('Your team, today and this week'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/crm/quiz/results'),
          ),
        ],
      ],
    );
  }
}

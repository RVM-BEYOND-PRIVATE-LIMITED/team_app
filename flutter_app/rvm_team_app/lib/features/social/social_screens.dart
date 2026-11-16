import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/team_stage2_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import '../stage2/stage2_shared.dart';
import '../tasks/tasks_screen.dart';

/// `/social` — Marketing's Needs attention or an editor's own cards (#54).
class SocialHomeScreen extends StatefulWidget {
  const SocialHomeScreen({super.key});
  @override
  State<SocialHomeScreen> createState() => _SocialHomeScreenState();
}

class _SocialHomeScreenState extends State<SocialHomeScreen> {
  Future<(SocialMe, SocialHome?)>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _future = _loadAll();
      });

  Future<(SocialMe, SocialHome?)> _loadAll() async {
    final repo = stage2Repository();
    final me = await repo.socialMe();
    SocialHome? home;
    if (me.role == 'marketing') home = await repo.socialHome();
    return (me, home);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Social media'),
        actions: [
          IconButton(
              tooltip: 'Board',
              onPressed: () => context.push('/social/board'),
              icon: const Icon(Icons.view_kanban_outlined)),
          IconButton(
              tooltip: 'Calendar',
              onPressed: () => context.push('/social/calendar'),
              icon: const Icon(Icons.calendar_month_outlined)),
          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<(SocialMe, SocialHome?)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return stage2Failure(
                snapshot.error is Failure ? snapshot.error as Failure : null,
                onRetry: _load);
          }
          final (me, home) = snapshot.data!;
          if (me.role == 'editor') return _EditorHome(me: me);
          if (home == null) return stage2Empty('No social access.');
          return ListView(
            padding: const EdgeInsets.all(RvmSpacing.md),
            children: [
              Stage2Section(title: 'Needs attention', children: [
                if (home.stuck.isEmpty && home.kitty.isEmpty)
                  TeamCard(child: Text('Nothing is stuck.')),
                for (final card in home.stuck.take(8)) _CardTile(card: card),
                for (final card in home.kitty.take(8)) _CardTile(card: card),
              ]),
              const SizedBox(height: RvmSpacing.lg),
              Stage2Section(title: 'Today', children: [
                for (final card in home.todayPosts) _CardTile(card: card),
                for (final shoot in home.todayShoots)
                  ShootCard(shoot: shoot),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _EditorHome extends StatefulWidget {
  const _EditorHome({required this.me});
  final SocialMe me;
  @override
  State<_EditorHome> createState() => _EditorHomeState();
}

class _EditorHomeState extends State<_EditorHome> {
  Future<List<SocialCard>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().socialCards());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SocialCard>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return stage2Failure(
                snapshot.error is Failure ? snapshot.error as Failure : null,
                onRetry: _load);
          }
          final cards = snapshot.data ?? const [];
          final todo = cards.where((c) => c.stage == 'todo').toList();
          final done = cards.where((c) => c.stage == 'done').toList();
          final next = cards
              .where((c) => c.stage == 'scheduled' || c.stage == 'live')
              .toList();
          return ListView(
            padding: const EdgeInsets.all(RvmSpacing.md),
            children: [
              for (final group in [
                ('Today', todo),
                ('Done', done),
                ('Next', next),
              ])
                Stage2Section(
                  title: group.$1,
                  children: [
                    if (group.$2.isEmpty)
                      TeamCard(child: Text('Nothing here.')),
                    for (final card in group.$2) _CardTile(card: card),
                  ],
                ),
            ],
          );
        },
      );
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.card});
  final SocialCard card;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TeamCard(
      onTap: () => context.push('/social/card/${card.id}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                    '${card.stage}'
                    '${card.editorName == null ? '' : ' · ${card.editorName}'}'
                    '${card.accounts.isEmpty ? '' : ' · ${card.accounts.map((a) => a.name).join(', ')}'}',
                    style: Theme.of(context).textTheme.bodySmall),
                if (card.postDate != null)
                  Text('Post ${card.postDate}',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: p.muted)),
              ],
            ),
          ),
          if (card.stage == 'todo')
            FilledButton(
              onPressed: () async {
                try {
                  await stage2Repository().markCardDone(card.id,
                      key: 'done-${DateTime.now().microsecondsSinceEpoch}');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Marked Done.')));
                  }
                } on Failure catch (failure) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(failure.message)));
                  }
                }
              },
              child: const Text('Done'),
            ),
        ],
      ),
    );
  }
}

/// `/social/board` — To do, Done, Scheduled, Live; one tap moves a card.
class SocialBoardScreen extends StatefulWidget {
  const SocialBoardScreen({super.key});
  @override
  State<SocialBoardScreen> createState() => _SocialBoardScreenState();
}

class _SocialBoardScreenState extends State<SocialBoardScreen> {
  Future<List<SocialCard>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().socialCards());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Board')),
      body: FutureBuilder<List<SocialCard>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return stage2Failure(
                snapshot.error is Failure ? snapshot.error as Failure : null,
                onRetry: _load);
          }
          final cards = snapshot.data ?? const [];
          return ListView(
            padding: const EdgeInsets.all(RvmSpacing.md),
            children: [
              for (final stage in ['todo', 'done', 'scheduled', 'live'])
                Stage2Section(
                  title: stage[0].toUpperCase() + stage.substring(1),
                  children: [
                    for (final card in cards.where((c) => c.stage == stage))
                      _BoardCard(card: card, onMoved: _load),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.card, required this.onMoved});
  final SocialCard card;
  final VoidCallback onMoved;

  @override
  Widget build(BuildContext context) {
    final next = switch (card.stage) {
      'todo' => 'done',
      'done' => 'scheduled',
      _ => null,
    };
    return TeamCard(
      onTap: () => context.push('/social/card/${card.id}').then((_) => onMoved()),
      child: Row(
        children: [
          Expanded(child: Text(card.title)),
          if (next != null)
            TextButton(
              onPressed: () async {
                try {
                  await stage2Repository().moveCard(card.id, {'stage': next},
                      key: 'move-${DateTime.now().microsecondsSinceEpoch}');
                  onMoved();
                } on Failure catch (failure) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(failure.message)));
                  }
                }
              },
              child: Text('Move to $next'),
            ),
        ],
      ),
    );
  }
}

/// `/social/card/:id` — one card with its brief and history (#54 item 7).
class SocialCardScreen extends StatefulWidget {
  const SocialCardScreen({super.key, required this.cardId});
  final String cardId;
  @override
  State<SocialCardScreen> createState() => _SocialCardScreenState();
}

class _SocialCardScreenState extends State<SocialCardScreen> {
  Future<SocialCard>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = stage2Repository().socialCard(widget.cardId));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Card')),
        body: FutureBuilder<SocialCard>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoading();
            }
            if (snapshot.hasError) {
              return stage2Failure(
                  snapshot.error is Failure ? snapshot.error as Failure : null,
                  onRetry: _load);
            }
            final card = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(RvmSpacing.md),
              children: [
                TeamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.title,
                          style: Theme.of(context).textTheme.titleLarge),
                      Text('${card.stage} · ${card.kind}'),
                      if (card.editorName != null)
                        Text('Editor: ${card.editorName}'),
                      if (card.accounts.isNotEmpty)
                        Text('Accounts: ${card.accounts.map((a) => a.name).join(', ')}'),
                      if (card.deadline != null) Text('Deadline: ${card.deadline}'),
                      if (card.postDate != null) Text('Post: ${card.postDate}'),
                    ],
                  ),
                ),
                const SizedBox(height: RvmSpacing.md),
                TeamSectionHeader(title: 'Brief'),
                const SizedBox(height: RvmSpacing.sm),
                TeamCard(
                  child: Text(card.brief.isEmpty
                      ? 'No brief.'
                      : card.brief.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join('\n')),
                ),
              ],
            );
          },
        ),
      );
}

/// `/social/calendar` — cards and shoots for the next 30 days (#54 item 11).
class SocialCalendarScreen extends StatefulWidget {
  const SocialCalendarScreen({super.key});
  @override
  State<SocialCalendarScreen> createState() => _SocialCalendarScreenState();
}

class _SocialCalendarScreenState extends State<SocialCalendarScreen> {
  Future<(List<SocialCard>, List<SocialShoot>, List<SocialAccount>)>? _future;
  String? _account;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _future = _loadAll();
      });

  Future<(List<SocialCard>, List<SocialShoot>, List<SocialAccount>)> _loadAll() async {
    final repo = stage2Repository();
    final cards = await repo.socialCards(account: _account);
    final shoots = await repo.shoots();
    final accounts = await repo.socialAccounts();
    return (cards, shoots, accounts);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Calendar')),
        body: FutureBuilder<(List<SocialCard>, List<SocialShoot>, List<SocialAccount>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoading();
            }
            if (snapshot.hasError) {
              return stage2Failure(
                  snapshot.error is Failure ? snapshot.error as Failure : null,
                  onRetry: _load);
            }
            final (cards, shoots, accounts) = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(RvmSpacing.md),
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: _account,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('All accounts')),
                    for (final a in accounts)
                      DropdownMenuItem<String?>(
                          value: a.id, child: Text('${a.brand} · ${a.name}')),
                  ],
                  onChanged: (v) {
                    _account = v;
                    _load();
                  },
                ),
                const SizedBox(height: RvmSpacing.md),
                Stage2Section(title: 'Posts', children: [
                  for (final c in cards) _CardTile(card: c),
                ]),
                const SizedBox(height: RvmSpacing.md),
                Stage2Section(title: 'Shoots', children: [
                  for (final s in shoots) ShootCard(shoot: s),
                ]),
              ],
            );
          },
        ),
      );
}

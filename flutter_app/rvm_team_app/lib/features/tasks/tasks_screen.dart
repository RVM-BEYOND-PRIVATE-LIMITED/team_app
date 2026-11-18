import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../domain/team_stage2_models.dart';
import '../../widgets/states.dart';
import '../../widgets/team_kit.dart';
import '../stage2/stage2_shared.dart';

/// `/tasks` — everyone's shoots (#54 item 2). Tagged staff are told, never
/// asked to accept or decline.
class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});
  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  Future<List<SocialShoot>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        final repo = stage2RepositoryOrNull();
        _future = repo == null ? Future.value(const []) : repo.myShoots();
      });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('My Tasks'),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<List<SocialShoot>>(
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
          final shoots = snapshot.data ?? const [];
          if (shoots.isEmpty) return stage2Empty('No shoots for you.');
          return ListView.separated(
            padding: const EdgeInsets.all(RvmSpacing.md),
            itemCount: shoots.length,
            separatorBuilder: (_, __) => const SizedBox(height: RvmSpacing.sm),
            itemBuilder: (_, i) => ShootCard(shoot: shoots[i]),
          );
        },
      ),
    );
  }
}

class ShootCard extends StatelessWidget {
  const ShootCard({super.key, required this.shoot});
  final SocialShoot shoot;

  @override
  Widget build(BuildContext context) => TeamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shoot.title ?? 'Shoot',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${shoot.day} · ${shoot.startTime} · ${shoot.minutes} min'),
            Text(shoot.place),
            if (shoot.prepare.isNotEmpty) Text('Prepare: ${shoot.prepare}'),
            if (shoot.people.isNotEmpty)
              Text('With: ${shoot.people.map((p) => p.name).join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (shoot.cuts > 0)
              Text(shoot.progressLabel,
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

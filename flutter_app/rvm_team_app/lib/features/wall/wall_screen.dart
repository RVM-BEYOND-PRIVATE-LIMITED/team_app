import 'package:flutter/material.dart';

import '../../widgets/coming_soon.dart';
import '../../widgets/team_header.dart';

/// The community feed (posts, reactions, comments, praise, polls,
/// announcements). The Scheduler has no Wall backend yet, so this tab is an
/// honest placeholder rather than a fake feed.
class WallScreen extends StatelessWidget {
  const WallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: const [
          TeamPageHeader(
            title: 'Wall',
            subtitle: Text('Company feed, praise and announcements'),
          ),
          Expanded(
            child: BackendPending(
              title: 'The Wall is not available yet',
              detail: 'Posts, reactions, comments, praise, polls and acknowledged '
                  'announcements need the new ESS backend (/api/ess/feed). The web '
                  'has no Wall today.',
              icon: Icons.forum_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

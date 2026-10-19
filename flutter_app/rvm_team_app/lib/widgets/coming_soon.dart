import 'package:flutter/material.dart';

/// Honest placeholder for a Team RVM feature whose backend does not exist yet.
/// It names the missing piece rather than pretending the feature works.
class BackendPending extends StatelessWidget {
  const BackendPending({
    super.key,
    required this.title,
    required this.detail,
    this.icon = Icons.construction_outlined,
  });

  final String title;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Chip(
              avatar: const Icon(Icons.hourglass_empty, size: 16),
              label: const Text('Backend not available yet'),
              backgroundColor: scheme.surfaceContainerHighest,
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ],
        ),
      ),
    );
  }
}

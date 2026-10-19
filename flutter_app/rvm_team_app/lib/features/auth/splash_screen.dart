import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

/// Shown while the stored session is probed; the router then moves to /login or
/// /home. It never lingers — it only states what is happening.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: RvmColors.teamSeed,
                borderRadius: BorderRadius.circular(RvmRadii.md),
              ),
              child: const Text('rvm',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
            ),
            const SizedBox(height: RvmSpacing.lg),
            Text('Team RVM', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: RvmSpacing.lg),
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
          ],
        ),
      ),
    );
  }
}

import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

/// Shown while the stored session is probed; the router then moves to /login or
/// /home. It never lingers — it only states what is happening.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [RvmColors.ironwood, RvmColors.ironwoodEnd],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/branding/team_rvm_mark.png',
                height: 38,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: RvmSpacing.lg),
              Text('Team RVM',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: RvmColors.ivory, fontWeight: FontWeight.w700)),
              const SizedBox(height: RvmSpacing.lg),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: RvmColors.ivory),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

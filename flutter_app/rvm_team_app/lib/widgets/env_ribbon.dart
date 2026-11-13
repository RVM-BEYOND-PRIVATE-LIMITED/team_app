import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

/// Switches the TEST SERVER ribbon on (team_app #60). Off unless a build
/// passes `--dart-define=SHOW_ENV_RIBBON=true`, so no build shows it by
/// accident.
const bool showEnvRibbon =
    bool.fromEnvironment('SHOW_ENV_RIBBON', defaultValue: false);

/// A TEST SERVER corner ribbon over the whole app when the build talks to a
/// server that is not production, so a screenshot or a pilot phone never
/// passes test data off as real (team_app #60). It never shows against the
/// live servers, and never while [enabled] is off.
class EnvRibbon extends StatelessWidget {
  const EnvRibbon({
    super.key,
    required this.environment,
    required this.child,
    this.enabled = showEnvRibbon,
  });

  final ApiEnvironment environment;
  final Widget child;
  final bool enabled;

  static const label = 'TEST SERVER';

  @override
  Widget build(BuildContext context) {
    if (!enabled || environment.isProduction) return child;
    return Banner(
      message: label,
      location: BannerLocation.topEnd,
      color: RvmColors.danger,
      // Small enough for both words to sit inside the corner.
      textStyle: const TextStyle(
        color: RvmColors.white,
        fontSize: 8.5,
        fontWeight: FontWeight.w800,
        height: 1.0,
      ),
      child: child,
    );
  }
}

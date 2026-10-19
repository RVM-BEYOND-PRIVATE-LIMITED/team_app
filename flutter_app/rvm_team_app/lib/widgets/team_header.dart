import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The one header every bottom-tab screen wears, so Home · Inbox · Wall · Me ·
/// My Team read as a single, finished app instead of five separate screens.
///
/// It paints the brand "Ironwood" gradient full-bleed behind the status bar
/// (with light status icons), reserves the top safe-area inset, and rounds its
/// bottom corners. Callers pass a [title] and, optionally, an [eyebrow] line
/// above it, a [subtitle] below it, a [leading] avatar/icon, trailing [actions]
/// and a [footer] row (e.g. a role pill and a location).
class TeamPageHeader extends StatelessWidget {
  const TeamPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.footer,
  });

  final String title;
  final String? eyebrow;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? footer;

  static const _gradientEnd = Color(0xFF52201A);
  static const _onHeader = RvmColors.ivory;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [RvmColors.ironwood, _gradientEnd],
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(RvmRadii.lg)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                RvmSpacing.md, RvmSpacing.sm, RvmSpacing.sm, RvmSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: RvmSpacing.md)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null)
                        Text(eyebrow!,
                            style: text.labelMedium?.copyWith(color: _onHeader.withValues(alpha: 0.75))),
                      if (eyebrow != null) const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.headlineSmall?.copyWith(
                            color: _onHeader, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: RvmSpacing.xs),
                        DefaultTextStyle.merge(
                          style: text.bodySmall?.copyWith(color: _onHeader.withValues(alpha: 0.85)) ??
                              const TextStyle(),
                          child: subtitle!,
                        ),
                      ],
                      if (footer != null) ...[
                        const SizedBox(height: RvmSpacing.sm),
                        footer!,
                      ],
                    ],
                  ),
                ),
                if (actions.isNotEmpty)
                  IconButtonTheme(
                    data: IconButtonThemeData(
                      style: IconButton.styleFrom(foregroundColor: _onHeader),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small pill for an [TeamPageHeader] footer — e.g. the signed-in role.
class TeamHeaderPill extends StatelessWidget {
  const TeamHeaderPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: RvmSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: RvmColors.teamSeed,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}

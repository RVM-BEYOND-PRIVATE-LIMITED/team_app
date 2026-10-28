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
/// and a [footer] row (e.g. a role pill, a location or a segmented control).
class TeamPageHeader extends StatelessWidget {
  const TeamPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.footer,
    this.titleTrailing,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 12, 20),
  });

  final String title;
  final String? eyebrow;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? footer;
  final Widget? titleTrailing;
  final EdgeInsetsGeometry padding;

  static const _onHeader = RvmColors.ivory;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final effectiveLeading = leading ??
        (canPop
            ? _HeaderBack(onTap: () => Navigator.of(context).maybePop())
            : null);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [RvmColors.ironwood, RvmColors.ironwoodEnd],
          ),
          borderRadius:
              BorderRadius.vertical(bottom: Radius.circular(RvmRadii.xl)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (effectiveLeading != null) ...[
                      effectiveLeading,
                      const SizedBox(width: 12)
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (eyebrow != null)
                            Text(
                              eyebrow!.toUpperCase(),
                              style: text.labelSmall?.copyWith(
                                color: _onHeader.withValues(alpha: 0.62),
                                fontSize: 9.5,
                                letterSpacing: 0.9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (eyebrow != null) const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.headlineSmall?.copyWith(
                                    color: _onHeader,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ),
                              if (titleTrailing != null) ...[
                                const SizedBox(width: 8),
                                titleTrailing!,
                              ],
                            ],
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            DefaultTextStyle.merge(
                              style: text.bodySmall?.copyWith(
                                    color: _onHeader.withValues(alpha: 0.68),
                                    fontSize: 12,
                                  ) ??
                                  const TextStyle(),
                              child: subtitle!,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Row(mainAxisSize: MainAxisSize.min, children: actions),
                    ],
                  ],
                ),
                if (footer != null) ...[
                  const SizedBox(height: RvmSpacing.md),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pinned page header for the five bottom tabs. It shows the full
/// [TeamPageHeader] at rest and collapses to a compact title/action line as the
/// page scrolls, like a Material collapsing toolbar.
class TeamCollapsingHeader extends StatelessWidget {
  const TeamCollapsingHeader({
    super.key,
    required this.expanded,
    required this.title,
    this.actions = const <Widget>[],
    this.contentHeight = 124,
    this.showBrandMark = true,
  });

  final Widget expanded;
  final String title;
  final List<Widget> actions;

  /// Whether the compact bar keeps the RVM wordmark visible once the expanded
  /// header has scrolled away.
  final bool showBrandMark;

  /// The expanded header's height below the status bar.
  final double contentHeight;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _TeamCollapsingHeaderDelegate(
        expanded: expanded,
        title: title,
        actions: actions,
        showBrandMark: showBrandMark,
        topPadding: top,
        maxExtent: top + contentHeight,
        minExtent: top + 52,
      ),
    );
  }
}

class _TeamCollapsingHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TeamCollapsingHeaderDelegate({
    required this.expanded,
    required this.title,
    required this.actions,
    required this.showBrandMark,
    required this.topPadding,
    required this.maxExtent,
    required this.minExtent,
  });

  final Widget expanded;
  final String title;
  final List<Widget> actions;
  final bool showBrandMark;
  final double topPadding;
  @override
  final double maxExtent;
  @override
  final double minExtent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final current = (maxExtent - shrinkOffset).clamp(minExtent, maxExtent);
    final expandedOpacity = (1 - t * 1.4).clamp(0.0, 1.0);
    final compactOpacity = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: SizedBox(
        height: current,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [RvmColors.ironwood, RvmColors.ironwoodEnd],
                    ),
                    borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(RvmRadii.xl)),
                  ),
                ),
              ),
              if (expandedOpacity > 0.01)
                Positioned(
                  left: 0,
                  right: 0,
                  top: -shrinkOffset,
                  height: maxExtent,
                  child: IgnorePointer(
                    ignoring: expandedOpacity < 0.9,
                    child: Opacity(opacity: expandedOpacity, child: expanded),
                  ),
                ),
              if (compactOpacity > 0.01)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: minExtent,
                  child: IgnorePointer(
                    ignoring: compactOpacity < 0.2,
                    child: Opacity(
                      opacity: compactOpacity,
                      child: _CompactHeaderBar(
                        title: title,
                        actions: actions,
                        showBrandMark: showBrandMark,
                        topPadding: topPadding,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TeamCollapsingHeaderDelegate old) =>
      old.expanded != expanded ||
      old.title != title ||
      old.actions != actions ||
      old.showBrandMark != showBrandMark ||
      old.topPadding != topPadding ||
      old.maxExtent != maxExtent ||
      old.minExtent != minExtent;
}

class _CompactHeaderBar extends StatelessWidget {
  const _CompactHeaderBar({
    required this.title,
    required this.actions,
    required this.showBrandMark,
    required this.topPadding,
  });

  final String title;
  final List<Widget> actions;
  final bool showBrandMark;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(top: topPadding, left: 16, right: 8),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(
                  color: RvmColors.ivory,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (showBrandMark) ...[
              const SizedBox(width: 8),
              const TeamBrandMark(size: 20),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 8),
              Row(mainAxisSize: MainAxisSize.min, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Team RVM wordmark for a page header: transparent, brand orange, and
/// sized by its height so the rvm stays legible without a box or border.
class TeamBrandMark extends StatelessWidget {
  const TeamBrandMark({super.key, this.size = 22});

  /// The rendered height of the wordmark; its width follows the asset's ratio.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Image.asset(
        'assets/branding/team_rvm_mark.png',
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.business_rounded,
          size: size,
          color: RvmColors.ivory,
        ),
      ),
    );
  }
}

/// A translucent circular action for an [TeamPageHeader] — e.g. refresh or
/// notifications. Pass [badge] to show the org/orange notification dot.
class TeamHeaderAction extends StatelessWidget {
  const TeamHeaderAction({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.09),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              icon: Icon(icon, size: 19, color: RvmColors.ivory),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (badge)
            Positioned(
              right: 8,
              top: 7,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: RvmColors.teamSeed,
                  shape: BoxShape.circle,
                  border: Border.all(color: RvmColors.ironwood, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small pill for a [TeamPageHeader] footer — e.g. the signed-in role.
class TeamHeaderPill extends StatelessWidget {
  const TeamHeaderPill({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: RvmColors.teamSeed,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: Colors.white),
            const SizedBox(width: 4)
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _HeaderBack extends StatelessWidget {
  const _HeaderBack({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 15, color: RvmColors.ivory),
      ),
    );
  }
}

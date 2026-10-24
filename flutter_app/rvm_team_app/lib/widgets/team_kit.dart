import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

/// Shared building blocks for the Team RVM design language: warm ivory canvas,
/// white cards with hairline sand borders, pill badges, soft icon tiles and
/// segmented controls. Every screen uses these so the app reads as one product.

// ── layout ────────────────────────────────────────────────────────────────

/// A page with the standard ivory canvas. Pass [header] for the ironwood
/// banner used by top-level tabs, or [title] for the compact centered app bar
/// used by pushed screens.
class TeamScaffold extends StatelessWidget {
  const TeamScaffold({
    super.key,
    this.header,
    this.title,
    this.actions,
    this.leading,
    this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget? header;
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: RvmColors.ivory,
      appBar: header != null
          ? null
          : AppBar(
              title: title == null ? null : Text(title!),
              leading: leading,
              actions: actions,
            ),
      body: header == null
          ? body
          : Column(
              children: [
                header!,
                Expanded(child: body ?? const SizedBox.shrink()),
              ],
            ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// A white card with the reference's 18px radius and hairline sand border.
class TeamCard extends StatelessWidget {
  const TeamCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(RvmSpacing.md),
    this.margin,
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = RvmRadii.lg,
  });

  final Widget? child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(padding: padding, child: child);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: color ?? theme.cardColor,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor ?? theme.dividerColor),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Section heading: an optional leading dot, a title, an optional count badge,
/// a muted caption and a trailing action/link.
class TeamSectionHeader extends StatelessWidget {
  const TeamSectionHeader({
    super.key,
    required this.title,
    this.caption,
    this.count,
    this.trailing,
    this.padding = EdgeInsets.zero,
    this.dotColor,
  });

  final String title;
  final String? caption;
  final String? count;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (dotColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: RvmSpacing.sm),
          ],
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium
                    ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          if (count != null) ...[
            const SizedBox(width: RvmSpacing.sm),
            TeamPill(label: count!, tone: TeamPillTone.neutral),
          ],
          if (caption != null) ...[
            const SizedBox(width: RvmSpacing.sm),
            Flexible(
              child: Text(caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: RvmColors.muted)),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ── pills & badges ────────────────────────────────────────────────────────

enum TeamPillTone {
  neutral,
  clay,
  orange,
  success,
  warning,
  danger,
  info,
  dark,
  onDark
}

class TeamPill extends StatelessWidget {
  const TeamPill({
    super.key,
    required this.label,
    this.tone = TeamPillTone.neutral,
    this.icon,
    this.dot = false,
    this.dense = false,
  });

  final String label;
  final TeamPillTone tone;
  final IconData? icon;
  final bool dot;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (tone) {
      TeamPillTone.neutral => (
          RvmColors.white,
          RvmColors.muted,
          RvmColors.line
        ),
      TeamPillTone.clay => (
          RvmColors.claySoft,
          RvmColors.clay,
          RvmColors.claySoft
        ),
      TeamPillTone.orange => (
          const Color(0xFFFCEBE2),
          const Color(0xFFB44E25),
          const Color(0xFFF7DCCD)
        ),
      TeamPillTone.success => (
          RvmColors.successSoft,
          RvmColors.success,
          const Color(0xFFCDEBDC)
        ),
      TeamPillTone.warning => (
          RvmColors.warningSoft,
          const Color(0xFF9A6A08),
          const Color(0xFFF3E4BC)
        ),
      TeamPillTone.danger => (
          RvmColors.dangerSoft,
          RvmColors.danger,
          const Color(0xFFF3D4D0)
        ),
      TeamPillTone.info => (
          RvmColors.infoSoft,
          RvmColors.info,
          const Color(0xFFD9E2FA)
        ),
      TeamPillTone.dark => (
          RvmColors.ironwood,
          RvmColors.ivory,
          RvmColors.ironwood
        ),
      TeamPillTone.onDark => (
          Colors.white.withValues(alpha: 0.13),
          RvmColors.ivory,
          Colors.white.withValues(alpha: 0.10)
        ),
    };
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontSize: dense ? 9.5 : 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 3 : 4.5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: textStyle),
        ],
      ),
    );
  }
}

/// Soft rounded-square icon tile used in cards, quick actions and sheets.
class TeamIconBadge extends StatelessWidget {
  const TeamIconBadge({
    super.key,
    required this.icon,
    this.color = RvmColors.clay,
    this.background = RvmColors.claySoft,
    this.size = 40,
    this.iconSize = 19,
    this.radius = 12,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

/// Initials avatar with the reference's warm gradient ring treatment.
class TeamAvatar extends StatelessWidget {
  const TeamAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 44,
    this.background,
    this.foreground = RvmColors.white,
    this.rounded = false,
    this.radius = 14,
  });

  final String name;
  final String? photoUrl;
  final double size;
  final Color? background;
  final Color foreground;
  final bool rounded;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final url = photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: rounded ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: rounded ? BorderRadius.circular(radius) : null,
        color: background ?? const Color(0xFFC67B5C),
        image: hasPhoto && !rounded
            ? DecorationImage(
                image: NetworkImage(url),
                fit: BoxFit.cover,
                // A dead avatar URL (offline DNS, expired link) must stay a
                // blank avatar, never an image error reaching the framework.
                onError: (_, __) {},
              )
            : null,
      ),
      clipBehavior: rounded ? Clip.antiAlias : Clip.none,
      alignment: Alignment.center,
      child: hasPhoto
          ? (rounded
              ? Image.network(url,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  errorBuilder: (_, __, ___) => Text(
                        initial,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: foreground,
                              fontSize: size * 0.38,
                              fontWeight: FontWeight.w700,
                            ),
                      ))
              : null)
          : Text(
              initial,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: foreground,
                    fontSize: size * 0.38,
                    fontWeight: FontWeight.w700,
                  ),
            ),
    );
  }
}

// ── controls ──────────────────────────────────────────────────────────────

/// Pill segmented control. Light by default; set [onDark] for the header
/// variant used on Time & Leave.
class TeamSegmentedTabs extends StatelessWidget {
  const TeamSegmentedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.counts,
    this.onDark = false,
    this.expand = true,
  });

  final List<String> labels;
  final List<String>? counts;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool onDark;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final track =
        onDark ? Colors.white.withValues(alpha: 0.13) : RvmColors.white;
    final selected = onDark ? RvmColors.white : RvmColors.claySoft;
    final selectedText = onDark ? RvmColors.ironwood : RvmColors.clay;
    final unselectedText =
        onDark ? RvmColors.ivory.withValues(alpha: 0.78) : RvmColors.muted;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color:
                onDark ? Colors.white.withValues(alpha: 0.08) : RvmColors.line),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            Flexible(
              flex: expand ? 1 : 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: i == selectedIndex ? selected : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          color: i == selectedIndex
                              ? selectedText
                              : unselectedText,
                          fontWeight: i == selectedIndex
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                      if (counts != null &&
                          i < counts!.length &&
                          counts![i].isNotEmpty) ...[
                        const SizedBox(width: 5),
                        TeamPill(
                          label: counts![i],
                          tone: onDark
                              ? TeamPillTone.onDark
                              : (i == selectedIndex
                                  ? TeamPillTone.clay
                                  : TeamPillTone.neutral),
                          dense: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A labelled field block used by the push screens: a tiny uppercase label
/// above the value or input.
class TeamFieldLabel extends StatelessWidget {
  const TeamFieldLabel(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: RvmColors.muted,
                  fontSize: 10.5,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class TeamProgressBar extends StatelessWidget {
  const TeamProgressBar(
      {super.key,
      required this.value,
      this.color = RvmColors.clay,
      this.height = 5});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        color: color,
        backgroundColor: RvmColors.sand,
      ),
    );
  }
}

// ── rows and notices ──────────────────────────────────────────────────────

/// A soft notice block (device status, warnings, hints).
class TeamNotice extends StatelessWidget {
  const TeamNotice({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.tone = TeamPillTone.clay,
    this.title,
    this.trailing,
  });

  final String text;
  final IconData icon;
  final TeamPillTone tone;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      TeamPillTone.warning => (RvmColors.warningSoft, RvmColors.warning),
      TeamPillTone.danger => (RvmColors.dangerSoft, RvmColors.danger),
      TeamPillTone.success => (RvmColors.successSoft, RvmColors.success),
      TeamPillTone.info => (RvmColors.infoSoft, RvmColors.info),
      TeamPillTone.orange => (const Color(0xFFFCEBE2), RvmColors.teamSeed),
      _ => (const Color(0xFFFCF3ED), RvmColors.clay),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(RvmRadii.md),
        border: Border.all(color: fg.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: RvmColors.ink)),
                  const SizedBox(height: 2),
                ],
                Text(text,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: RvmColors.muted, height: 1.4)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Label/value row used inside detail cards.
class TeamInfoRow extends StatelessWidget {
  const TeamInfoRow(
      {super.key,
      required this.label,
      required this.value,
      this.valueColor,
      this.mono = false});
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: RvmColors.muted))),
          const SizedBox(width: RvmSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: valueColor ?? RvmColors.ink,
                    fontWeight: FontWeight.w600,
                    fontFeatures:
                        mono ? const [FontFeature.tabularFigures()] : null,
                    letterSpacing: mono ? 0.4 : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single metric tile: large value, unit and uppercase caption.
class TeamMetricTile extends StatelessWidget {
  const TeamMetricTile({
    super.key,
    required this.value,
    required this.label,
    this.tone = RvmColors.clay,
    this.soft = RvmColors.cream,
    this.unit,
    this.onTap,
  });

  final String value;
  final String label;
  final Color tone;
  final Color soft;
  final String? unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: soft,
      borderRadius: BorderRadius.circular(RvmRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RvmRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RvmRadii.md),
            border: Border.all(color: tone.withValues(alpha: 0.10)),
          ),
          child: Column(
            children: [
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: tone, fontSize: 20),
                  children: [
                    TextSpan(text: value),
                    if (unit != null)
                      TextSpan(
                        text: ' $unit',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: RvmColors.muted),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 8.5,
                      letterSpacing: 0.5,
                      color: RvmColors.muted,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The large full-width pill button used for primary actions (Punch in, Save).
class TeamPrimaryButton extends StatelessWidget {
  const TeamPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.color = RvmColors.clay,
    this.height = 54,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(backgroundColor: color),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 15, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(label,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1)),
                ],
              ),
      ),
    );
  }
}

/// A bottom-sheet body with the reference's title row and close button.
class TeamSheetHeader extends StatelessWidget {
  const TeamSheetHeader(
      {super.key, required this.title, this.icon, this.onClose, this.trailing});
  final String title;
  final IconData? icon;
  final VoidCallback? onClose;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          TeamIconBadge(icon: icon!, size: 34, iconSize: 17),
          const SizedBox(width: 10),
        ],
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (trailing != null) trailing!,
        if (onClose != null)
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

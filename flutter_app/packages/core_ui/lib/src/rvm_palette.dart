import 'package:flutter/material.dart';

/// Semantic colours for the Team RVM design system.
///
/// Every theme-dependent surface, text, border and status colour lives here.
/// Screens must read a role from [RvmPalette] (or `ColorScheme`) instead of
/// using a raw `RvmColors` constant, so Light and Dark render correctly.
///
/// Light keeps the warm ivory/clay identity. Dark is built on Ironwood
/// (`#1C0E0B`) with Forge Orange as the action colour. Both palettes are
/// checked by `palette_contrast_test.dart` for WCAG AA body text.
@immutable
class RvmPalette extends ThemeExtension<RvmPalette> {
  const RvmPalette({
    required this.canvas,
    required this.surface,
    required this.card,
    required this.cardElevated,
    required this.sand,
    required this.ink,
    required this.inkSecondary,
    required this.muted,
    required this.subtle,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.brand,
    required this.onBrand,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.line,
    required this.outline,
    required this.isDark,
  });

  /// Page background.
  final Color canvas;

  /// A raised page surface (dialogs, sheets, large panels).
  final Color surface;

  /// Card and input surface.
  final Color card;

  /// A tinted card above [card].
  final Color cardElevated;

  /// Warm neutral fill for chips and quiet sections.
  final Color sand;

  /// Primary text.
  final Color ink;

  /// Secondary text that still needs AA contrast.
  final Color inkSecondary;

  /// Muted body text and labels.
  final Color muted;

  /// Hints and disabled text.
  final Color subtle;

  /// Clay / forge-orange action colour.
  final Color primary;
  final Color onPrimary;

  /// Terracotta accent used for live markers and links.
  final Color secondary;
  final Color onSecondary;

  /// Ironwood header band.
  final Color brand;
  final Color onBrand;

  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  /// Hairline card border.
  final Color line;

  /// Stronger control border.
  final Color outline;

  final bool isDark;

  /// Compatibility aliases used by the existing design system.
  Color get background => canvas;
  Color get header => brand;
  Color get onHeader => onBrand;
  Color get surfaceElevated => cardElevated;

  static const light = RvmPalette(
    canvas: Color(0xFFF9F6F1),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardElevated: Color(0xFFFDF8F1),
    sand: Color(0xFFF3EBE1),
    ink: Color(0xFF2D2420),
    inkSecondary: Color(0xFF4A3B33),
    // Was #8B7D73 (3.7:1). Darkened to meet AA on ivory and white.
    muted: Color(0xFF6E6157),
    // Was #B3A79D (2.4:1). Darkened to meet AA on white.
    subtle: Color(0xFF7B6E64),
    primary: Color(0xFF7D432E),
    onPrimary: Color(0xFFFFFFFF),
    // Was #C0562C (4.2:1). Darkened to meet AA on ivory.
    secondary: Color(0xFFB04E24),
    onSecondary: Color(0xFFFFFFFF),
    brand: Color(0xFF2E1712),
    onBrand: Color(0xFFF9F6F1),
    success: Color(0xFF147A52),
    successSoft: Color(0xFFE7F6EE),
    warning: Color(0xFF8A5A00),
    warningSoft: Color(0xFFFDF6E3),
    danger: Color(0xFFB23A30),
    dangerSoft: Color(0xFFFBECEA),
    info: Color(0xFF3D5BB5),
    infoSoft: Color(0xFFEEF2FD),
    line: Color(0xFFEDE4DA),
    outline: Color(0xFFD8CCBF),
    isDark: false,
  );

  static const dark = RvmPalette(
    canvas: Color(0xFF1C0E0B),
    surface: Color(0xFF26130F),
    card: Color(0xFF26130F),
    cardElevated: Color(0xFF331714),
    sand: Color(0xFF2E1A15),
    ink: Color(0xFFF3F5F4),
    inkSecondary: Color(0xFFE2D8D4),
    muted: Color(0xFFC9BBB6),
    subtle: Color(0xFFB7A7A2),
    primary: Color(0xFFF84E28),
    onPrimary: Color(0xFF2E1712),
    secondary: Color(0xFFF0A07F),
    onSecondary: Color(0xFF3A1A0F),
    brand: Color(0xFF2E1712),
    onBrand: Color(0xFFF3F5F4),
    success: Color(0xFF5BD6A0),
    successSoft: Color(0xFF123B2A),
    warning: Color(0xFFFFD166),
    warningSoft: Color(0xFF3C2E16),
    danger: Color(0xFFFF8A80),
    dangerSoft: Color(0xFF4A1F1B),
    info: Color(0xFF9DB7FF),
    infoSoft: Color(0xFF1E2A4A),
    line: Color(0xFF47302B),
    outline: Color(0xFF5C423B),
    isDark: true,
  );

  @override
  RvmPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? card,
    Color? cardElevated,
    Color? sand,
    Color? ink,
    Color? inkSecondary,
    Color? muted,
    Color? subtle,
    Color? primary,
    Color? onPrimary,
    Color? secondary,
    Color? onSecondary,
    Color? brand,
    Color? onBrand,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
    Color? line,
    Color? outline,
    bool? isDark,
  }) {
    return RvmPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      cardElevated: cardElevated ?? this.cardElevated,
      sand: sand ?? this.sand,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      muted: muted ?? this.muted,
      subtle: subtle ?? this.subtle,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      brand: brand ?? this.brand,
      onBrand: onBrand ?? this.onBrand,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      line: line ?? this.line,
      outline: outline ?? this.outline,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  RvmPalette lerp(covariant RvmPalette? other, double t) {
    if (other == null) return this;
    return RvmPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardElevated: Color.lerp(cardElevated, other.cardElevated, t)!,
      sand: Color.lerp(sand, other.sand, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      onSecondary: Color.lerp(onSecondary, other.onSecondary, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      line: Color.lerp(line, other.line, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// `context.rvmPalette` / `context.palette` -> the active [RvmPalette].
extension RvmPaletteContext on BuildContext {
  RvmPalette get rvmPalette =>
      Theme.of(this).extension<RvmPalette>() ?? RvmPalette.light;

  RvmPalette get palette => rvmPalette;
}

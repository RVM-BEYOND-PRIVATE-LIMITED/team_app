import 'package:flutter/material.dart';

/// Brand primitives shared across both apps. Change here => changes everywhere.
///
/// Team RVM's palette is taken from the 2026 design reference: ironwood-brown
/// headers, a warm ivory canvas, white cards with hairline sand borders, clay
/// primary actions and a forge-orange accent for links and live markers.
abstract final class RvmColors {
  static const brand = Color(0xFF7D432E); // clay — primary action
  static const studentSeed = Color(0xFF1E5EFF);
  static const staffSeed = Color(0xFF0F766E);
  static const teamSeed = Color(0xFFC0562C); // Forge Orange accent
  static const ironwood = Color(0xFF2E1712); // header top
  static const ironwoodEnd = Color(0xFF52201A); // header gradient end
  static const clay = Color(0xFF7D432E);
  static const clayDark = Color(0xFF673725);
  static const claySoft = Color(0xFFF6E9E1);
  static const ivory = Color(0xFFF9F6F1); // page canvas
  static const cream = Color(0xFFFDF8F1); // tinted fill
  static const sand = Color(0xFFF3EBE1);
  static const line = Color(0xFFEDE4DA); // hairline card border
  static const ink = Color(0xFF2D2420);
  static const muted = Color(0xFF8B7D73);
  static const subtle = Color(0xFFB3A79D);
  static const white = Color(0xFFFFFFFF);

  static const danger = Color(0xFFC5453A);
  static const dangerSoft = Color(0xFFFBECEA);
  static const success = Color(0xFF1F9D6B);
  static const successSoft = Color(0xFFE7F6EE);
  static const warning = Color(0xFFC58A12);
  static const warningSoft = Color(0xFFFDF6E3);
  static const info = Color(0xFF4E6FD0);
  static const infoSoft = Color(0xFFEEF2FD);
}

/// 4pt spacing scale.
abstract final class RvmSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class RvmRadii {
  static const xs = 8.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
}

/// The type scale used by the design reference. Plus Jakarta Sans is bundled in
/// `rvm_team_app/assets/fonts`; the family name is set by [RvmTheme].
abstract final class RvmType {
  static const family = 'PlusJakartaSans';

  static TextTheme textTheme(Color ink, Color muted) => TextTheme(
        displaySmall: TextStyle(
            fontFamily: family,
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: ink),
        headlineMedium: TextStyle(
            fontFamily: family,
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: ink),
        headlineSmall: TextStyle(
            fontFamily: family,
            fontSize: 20,
            height: 1.25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: ink),
        titleLarge: TextStyle(
            fontFamily: family,
            fontSize: 18,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: ink),
        titleMedium: TextStyle(
            fontFamily: family,
            fontSize: 15.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: ink),
        titleSmall: TextStyle(
            fontFamily: family,
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: ink),
        bodyLarge: TextStyle(
            fontFamily: family,
            fontSize: 14.5,
            height: 1.45,
            fontWeight: FontWeight.w400,
            color: ink),
        bodyMedium: TextStyle(
            fontFamily: family,
            fontSize: 13.5,
            height: 1.45,
            fontWeight: FontWeight.w400,
            color: ink),
        bodySmall: TextStyle(
            fontFamily: family,
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w400,
            color: muted),
        labelLarge: TextStyle(
            fontFamily: family,
            fontSize: 12.5,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: ink),
        labelMedium: TextStyle(
            fontFamily: family,
            fontSize: 11,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: muted),
        labelSmall: TextStyle(
            fontFamily: family,
            fontSize: 10,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: muted),
      );
}

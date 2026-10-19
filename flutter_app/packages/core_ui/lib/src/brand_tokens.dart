import 'package:flutter/material.dart';

/// Brand primitives shared across both apps. Change here => changes everywhere.
abstract final class RvmColors {
  static const brand = Color(0xFF1E5EFF); // RVM blue — default seed
  static const studentSeed = Color(0xFF1E5EFF);
  static const staffSeed = Color(0xFF0F766E); // teal, to distinguish staff app
  // Team RVM (Sept 2026 rebrand): Forge Orange accent, Ironwood ink.
  static const teamSeed = Color(0xFFF84E28); // Forge Orange
  static const ironwood = Color(0xFF331714);
  static const ivory = Color(0xFFF3F5F4);
  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
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
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
}

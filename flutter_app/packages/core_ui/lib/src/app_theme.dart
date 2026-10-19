import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// Builds the shared ThemeData. Each app passes its own [seed] so student and
/// staff apps look related but distinct.
abstract final class RvmTheme {
  static ThemeData light({Color seed = RvmColors.brand}) => _base(seed, Brightness.light);
  static ThemeData dark({Color seed = RvmColors.brand}) => _base(seed, Brightness.dark);

  static ThemeData _base(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RvmRadii.md),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RvmRadii.sm),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RvmRadii.sm),
          ),
        ),
      ),
    );
  }
}

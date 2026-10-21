import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand_tokens.dart';

/// Builds the shared ThemeData. Team RVM uses the warm "ironwood + ivory"
/// design language from the 2026 reference; the other apps keep their seeds.
abstract final class RvmTheme {
  static ThemeData light({Color seed = RvmColors.brand}) =>
      _base(seed, Brightness.light);
  static ThemeData dark({Color seed = RvmColors.brand}) =>
      _base(seed, Brightness.dark);

  static ThemeData _base(Color seed, Brightness brightness) {
    final light = brightness == Brightness.light;
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

    final ink = light ? RvmColors.ink : const Color(0xFFF6EFE9);
    final muted = light ? RvmColors.muted : const Color(0xFFB8A79C);
    final canvas = light ? RvmColors.ivory : const Color(0xFF1B1310);
    final card = light ? RvmColors.white : const Color(0xFF241A16);
    final line = light ? RvmColors.line : const Color(0xFF3A2B24);
    final sand = light ? RvmColors.sand : const Color(0xFF31241E);
    final primary = light ? RvmColors.clay : const Color(0xFFD0876A);
    final onPrimary = light ? RvmColors.white : const Color(0xFF2A120A);
    final primarySoft = light ? RvmColors.claySoft : const Color(0xFF3B241C);
    final accent = light ? RvmColors.teamSeed : const Color(0xFFE58A5E);

    final scheme = base.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primarySoft,
      onPrimaryContainer: light ? RvmColors.clayDark : const Color(0xFFFFDBCB),
      secondary: accent,
      onSecondary: RvmColors.white,
      secondaryContainer:
          light ? RvmColors.warningSoft : const Color(0xFF3C2E16),
      onSecondaryContainer:
          light ? RvmColors.clayDark : const Color(0xFFFFE2A8),
      tertiary: RvmColors.info,
      surface: canvas,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerHighest: sand,
      surfaceContainerHigh: light ? RvmColors.cream : sand,
      surfaceContainer: card,
      outline: light ? RvmColors.line : const Color(0xFF4A382F),
      outlineVariant: line,
      error: RvmColors.danger,
      onError: RvmColors.white,
      errorContainer: light ? RvmColors.dangerSoft : const Color(0xFF4A1F1B),
      onErrorContainer: light ? RvmColors.danger : const Color(0xFFFFC9C4),
    );

    final text =
        RvmType.textTheme(ink, muted).apply(bodyColor: ink, displayColor: ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: RvmType.family,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleMedium
            ?.copyWith(fontSize: 16.5, fontWeight: FontWeight.w600, color: ink),
        iconTheme: IconThemeData(color: ink, size: 22),
        systemOverlayStyle:
            light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RvmRadii.lg),
          side: BorderSide(color: line),
        ),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        hintStyle: text.bodyMedium?.copyWith(color: RvmColors.subtle),
        labelStyle:
            text.labelMedium?.copyWith(color: muted, letterSpacing: 0.5),
        floatingLabelStyle:
            text.labelMedium?.copyWith(color: primary, letterSpacing: 0.5),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: RvmColors.danger),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RvmRadii.md),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RvmRadii.md),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RvmRadii.md),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RvmRadii.md),
          borderSide: const BorderSide(color: RvmColors.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RvmRadii.md),
          borderSide: const BorderSide(color: RvmColors.danger, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: primarySoft,
          disabledForegroundColor: muted,
          elevation: 0,
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: text.labelLarge?.copyWith(
              fontSize: 14.5, fontWeight: FontWeight.w600, color: onPrimary),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(RvmRadii.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: card,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: text.labelLarge
              ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          side: BorderSide(
              color: light ? RvmColors.line : const Color(0xFF4A382F)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(RvmRadii.md)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(RvmRadii.sm)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: ink),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 3,
        highlightElevation: 5,
        extendedTextStyle: text.labelLarge
            ?.copyWith(color: onPrimary, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: primarySoft,
        disabledColor: sand,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RvmRadii.sm)),
        labelStyle: text.labelMedium
            ?.copyWith(color: muted, fontSize: 12, fontWeight: FontWeight.w500),
        secondaryLabelStyle: text.labelMedium
            ?.copyWith(color: primary, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        showCheckmark: false,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: ink,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minLeadingWidth: 20,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RvmRadii.xl)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: card,
        showDragHandle: true,
        dragHandleColor: RvmColors.subtle,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(RvmRadii.xl)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primarySoft,
        labelTextStyle: WidgetStatePropertyAll(
            text.labelSmall?.copyWith(fontSize: 10.5, letterSpacing: 0.1)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 21,
              color: states.contains(WidgetState.selected) ? primary : muted,
            )),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: canvas),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RvmRadii.md)),
        elevation: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: sand,
        circularTrackColor: sand,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? RvmColors.white : muted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : sand),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : Colors.transparent),
        side: BorderSide(color: light ? RvmColors.subtle : muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : muted),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RvmRadii.md),
          side: BorderSide(color: line),
        ),
        textStyle: text.bodyMedium,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorColor: primary,
        labelColor: primary,
        unselectedLabelColor: muted,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge?.copyWith(color: muted),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
            color: ink, borderRadius: BorderRadius.circular(RvmRadii.xs)),
        textStyle: text.bodySmall?.copyWith(color: canvas),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.22),
        selectionHandleColor: primary,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(muted.withValues(alpha: 0.4)),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(4),
      ),
    );
  }
}

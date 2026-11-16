import 'dart:math' as math;

import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color c) {
  double channel(double value) {
    final v = value <= 0.03928 ? value / 12.92 : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    return v;
  }

  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final l1 = _luminance(a);
  final l2 = _luminance(b);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('RvmPalette contrast (WCAG AA)', () {
    for (final entry in {
      'light': RvmPalette.light,
      'dark': RvmPalette.dark,
    }.entries) {
      final name = entry.key;
      final p = entry.value;

      test('$name body text meets 4.5:1', () {
        expect(contrast(p.ink, p.canvas), greaterThanOrEqualTo(4.5));
        expect(contrast(p.ink, p.card), greaterThanOrEqualTo(4.5));
        expect(contrast(p.inkSecondary, p.card), greaterThanOrEqualTo(4.5));
        expect(contrast(p.muted, p.canvas), greaterThanOrEqualTo(4.5));
        expect(contrast(p.muted, p.card), greaterThanOrEqualTo(4.5));
        expect(contrast(p.subtle, p.card), greaterThanOrEqualTo(4.5));
      });

      test('$name action and status inks meet 4.5:1', () {
        expect(contrast(p.primary, p.canvas), greaterThanOrEqualTo(4.5));
        expect(contrast(p.onPrimary, p.primary), greaterThanOrEqualTo(4.5));
        expect(contrast(p.secondary, p.canvas), greaterThanOrEqualTo(4.5));
        expect(contrast(p.success, p.successSoft), greaterThanOrEqualTo(4.5));
        expect(contrast(p.warning, p.warningSoft), greaterThanOrEqualTo(4.5));
        expect(contrast(p.danger, p.dangerSoft), greaterThanOrEqualTo(4.5));
        expect(contrast(p.info, p.infoSoft), greaterThanOrEqualTo(4.5));
        expect(contrast(p.onBrand, p.brand), greaterThanOrEqualTo(4.5));
      });
    }
  });

  test('both ThemeData carry the matching palette extension', () {
    final light = RvmTheme.light();
    final dark = RvmTheme.dark();
    expect(light.extension<RvmPalette>(), RvmPalette.light);
    expect(dark.extension<RvmPalette>(), RvmPalette.dark);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.scaffoldBackgroundColor, RvmPalette.light.canvas);
    expect(dark.scaffoldBackgroundColor, RvmPalette.dark.canvas);
  });

  test('copyWith and lerp preserve every role', () {
    final custom = RvmPalette.light.copyWith(primary: const Color(0xFF123456));
    expect(custom.primary, const Color(0xFF123456));
    expect(custom.canvas, RvmPalette.light.canvas);

    final mid = RvmPalette.light.lerp(RvmPalette.dark, 0.5);
    expect(mid.canvas, isNot(RvmPalette.light.canvas));
    expect(mid.canvas, isNot(RvmPalette.dark.canvas));
    expect(RvmPalette.dark.lerp(null, 0.5), RvmPalette.dark);
  });
}

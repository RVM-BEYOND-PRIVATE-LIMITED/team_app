import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// The three appearance choices the server stores.
///
/// The wire values are fixed by contracts/openapi.yaml 0.17.0:
/// `light`, `dark`, `system`.
enum ThemeChoice {
  system('system', ThemeMode.system),
  light('light', ThemeMode.light),
  dark('dark', ThemeMode.dark);

  const ThemeChoice(this.wire, this.mode);

  final String wire;
  final ThemeMode mode;

  static ThemeChoice fromWire(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'dark':
        return ThemeChoice.dark;
      case 'system':
        return ThemeChoice.system;
      default:
        return ThemeChoice.light;
    }
  }

  String get label => switch (this) {
        ThemeChoice.system => 'System default',
        ThemeChoice.light => 'Light',
        ThemeChoice.dark => 'Dark',
      };

  String get subtitle => switch (this) {
        ThemeChoice.system => "Follows your phone's setting",
        ThemeChoice.light => 'The warm Team RVM look',
        ThemeChoice.dark => 'Dark surfaces, lower glare',
      };
}

/// GET/PUT `/me/preferences` as defined by contract 0.17.0.
class ThemePreference extends Equatable {
  const ThemePreference({required this.choice, required this.open});

  /// While [open] is false the server always answers `light`.
  final ThemeChoice choice;

  /// Whether the `theme` switch is open to this person.
  final bool open;

  factory ThemePreference.fromJson(Map<String, dynamic> json) {
    return ThemePreference(
      choice: ThemeChoice.fromWire(json['theme']?.toString()),
      open: json['theme_open'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'theme': choice.wire,
        'theme_open': open,
      };

  @override
  List<Object?> get props => [choice, open];
}

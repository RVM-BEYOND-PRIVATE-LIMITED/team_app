import 'package:shared_preferences/shared_preferences.dart';

import 'theme_preference.dart';

/// Small local cache so a cold start paints the right theme before the network
/// answers. The server remains the source of truth.
abstract class ThemeLocalStore {
  Future<ThemePreference?> read();

  Future<void> write(ThemePreference preference);

  Future<void> clear();
}

class SharedPreferencesThemeStore implements ThemeLocalStore {
  SharedPreferencesThemeStore({SharedPreferences? preferences})
      : _provided = preferences;

  static const _themeKey = 'team_app.theme';
  static const _openKey = 'team_app.theme_open';

  final SharedPreferences? _provided;
  SharedPreferences? _cached;

  Future<SharedPreferences> get _prefs async =>
      _provided ?? (_cached ??= await SharedPreferences.getInstance());

  @override
  Future<ThemePreference?> read() async {
    final prefs = await _prefs;
    final theme = prefs.getString(_themeKey);
    if (theme == null) return null;
    return ThemePreference(
      choice: ThemeChoice.fromWire(theme),
      open: prefs.getBool(_openKey) ?? false,
    );
  }

  @override
  Future<void> write(ThemePreference preference) async {
    final prefs = await _prefs;
    await prefs.setString(_themeKey, preference.choice.wire);
    await prefs.setBool(_openKey, preference.open);
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_themeKey);
    await prefs.remove(_openKey);
  }
}

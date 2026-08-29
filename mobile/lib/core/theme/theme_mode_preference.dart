import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferência de tema do usuário: claro, escuro ou seguir sistema.
enum ThemeModePreference {
  light('Claro'),
  dark('Escuro'),
  system('Seguir Sistema');

  const ThemeModePreference(this.label);

  final String label;
}

/// Persistência de preferência de tema em SharedPreferences.
class ThemeModePreferenceStorage {
  static const _key = 'theme_mode_preference';

  Future<ThemeModePreference> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key) ?? 'system';
    return ThemeModePreference.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ThemeModePreference.system,
    );
  }

  Future<void> setMode(ThemeModePreference mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  /// Converte para ThemeMode para MaterialApp.
  static ThemeMode toThemeMode(ThemeModePreference preference) {
    return switch (preference) {
      ThemeModePreference.light => ThemeMode.light,
      ThemeModePreference.dark => ThemeMode.dark,
      ThemeModePreference.system => ThemeMode.system,
    };
  }
}

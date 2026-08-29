import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../../core/theme/theme_mode_preference.dart';
import 'home_layout_mode.dart';
import 'home_layout_preference.dart';
import 'home_design_style.dart';

final homeLayoutPreferenceProvider = Provider<HomeLayoutPreference>((ref) {
  return HomeLayoutPreference();
});

final homeLayoutModeProvider = FutureProvider.autoDispose<HomeLayoutMode>((ref) {
  return ref.watch(homeLayoutPreferenceProvider).getModo();
});

final homeDesignStyleProvider = FutureProvider.autoDispose<HomeDesignStyle>((ref) {
  return ref.watch(homeLayoutPreferenceProvider).getDesign();
});

final themeModePreferenceProvider = Provider<ThemeModePreferenceStorage>((ref) {
  return ThemeModePreferenceStorage();
});

final themeModeProvider = FutureProvider.autoDispose<ThemeModePreference>((ref) {
  return ref.watch(themeModePreferenceProvider).getMode();
});

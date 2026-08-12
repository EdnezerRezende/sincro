import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_layout_mode.dart';
import 'home_layout_preference.dart';

final homeLayoutPreferenceProvider = Provider<HomeLayoutPreference>((ref) {
  return HomeLayoutPreference();
});

final homeLayoutModeProvider = FutureProvider.autoDispose<HomeLayoutMode>((ref) {
  return ref.watch(homeLayoutPreferenceProvider).getModo();
});

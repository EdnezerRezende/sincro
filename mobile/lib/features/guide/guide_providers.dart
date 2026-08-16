import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'guide_preference.dart';

final guidePreferenceProvider = Provider<GuidePreference>((ref) {
  return GuidePreference();
});

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sincro_mobile/features/guide/guide_preference.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('getVersaoVista defaults to 0 when nothing was ever saved', () async {
    final pref = GuidePreference();

    expect(await pref.getVersaoVista(), 0);
  });

  test('setVersaoVista persists the value for later reads', () async {
    final pref = GuidePreference();

    await pref.setVersaoVista(1);

    expect(await pref.getVersaoVista(), 1);
  });
}

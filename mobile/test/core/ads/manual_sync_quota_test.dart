import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sincro_mobile/core/ads/manual_sync_quota.dart';

void main() {
  late DateTime agora;
  late ManualSyncQuota quota;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    agora = DateTime(2026, 3, 10, 9);
    quota = ManualSyncQuota(clock: () => agora);
  });

  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  test('sem limite configurado, nunca bloqueia', () async {
    for (var i = 0; i < 20; i++) {
      expect(await quota.tentarConsumir(null), isTrue);
    }
  });

  test('bloqueia ao atingir o limite e zera no dia seguinte', () async {
    expect(await quota.tentarConsumir(2), isTrue);
    expect(await quota.tentarConsumir(2), isTrue);
    expect(await quota.tentarConsumir(2), isFalse);

    agora = agora.add(const Duration(days: 1));
    expect(await quota.tentarConsumir(2), isTrue);
  });

  test('desbloqueio premiado libera até expirar', () async {
    expect(await quota.tentarConsumir(1), isTrue);
    expect(await quota.tentarConsumir(1), isFalse);

    await quota.desbloquear(const Duration(minutes: 60));
    expect(await quota.desbloqueadoAte(), isNotNull);
    expect(await quota.tentarConsumir(1), isTrue);
    expect(await quota.tentarConsumir(1), isTrue);

    agora = agora.add(const Duration(minutes: 61));
    expect(await quota.desbloqueadoAte(), isNull);
    expect(await quota.tentarConsumir(1), isFalse);
  });
}

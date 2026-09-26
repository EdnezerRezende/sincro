import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/ads/frequency_cap.dart';

void main() {
  test('permite a primeira exibição e bloqueia até passar o intervalo mínimo', () {
    var agora = DateTime(2026, 1, 1, 10);
    final cap = FrequencyCap(minInterval: const Duration(minutes: 3), clock: () => agora);

    expect(cap.canShow, isTrue);
    cap.markShown();
    expect(cap.canShow, isFalse);

    agora = agora.add(const Duration(minutes: 2, seconds: 59));
    expect(cap.canShow, isFalse);

    agora = agora.add(const Duration(seconds: 1));
    expect(cap.canShow, isTrue);
  });

  test('respeita um novo intervalo vindo dos feature flags', () {
    var agora = DateTime(2026, 1, 1, 10);
    final cap = FrequencyCap(minInterval: const Duration(minutes: 3), clock: () => agora)..markShown();

    agora = agora.add(const Duration(minutes: 1));
    cap.minInterval = const Duration(seconds: 30);
    expect(cap.canShow, isTrue);
  });
}

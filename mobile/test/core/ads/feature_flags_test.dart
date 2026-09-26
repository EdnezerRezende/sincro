import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/ads/feature_flags.dart';
import 'package:sincro_mobile/core/ads/sincro_banner_ad.dart';

void main() {
  test('interpreta a resposta de GET /users/me/features', () {
    final flags = FeatureFlags.fromJson({
      'plano': 'simples',
      'ads': {
        'enabled': true,
        'banner': true,
        'interstitial': false,
        'rewarded': true,
        'interstitialMinIntervalSeconds': 180,
        'rewardedUnlockMinutes': 30,
      },
      'limits': {'manualSyncsPerDay': 5},
    });

    expect(flags.plano, 'simples');
    expect(flags.ads.banner, isTrue);
    expect(flags.ads.interstitial, isFalse);
    expect(flags.ads.interstitialMinInterval, const Duration(minutes: 3));
    expect(flags.ads.rewardedUnlockDuration, const Duration(minutes: 30));
    expect(flags.manualSyncsPerDay, 5);
  });

  test('resposta incompleta resolve para tudo desligado e sem limite', () {
    final flags = FeatureFlags.fromJson({});

    expect(flags.ads.enabled, isFalse);
    expect(flags.ads.banner, isFalse);
    expect(flags.manualSyncsPerDay, isNull);
  });

  testWidgets('banner não ocupa espaço quando o toggle está desligado', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adsFlagsProvider.overrideWithValue(AdsFlags.off)],
        child: const MaterialApp(home: Scaffold(bottomNavigationBar: SincroBannerAd())),
      ),
    );

    expect(tester.getSize(find.byType(SincroBannerAd)).height, 0);
  });
}

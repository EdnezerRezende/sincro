import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/auth_providers.dart';
import '../api_providers.dart';

/// Espelho de `GET /users/me/features` (ver `backend/src/users/feature-flags.ts`).
///
/// A decisão de mostrar ou não anúncios fica no backend (que conhece o `plano` do usuário) para
/// que, quando existir um plano pago, quem assina deixe de ver anúncios sem uma nova versão do app.
class AdsFlags {
  const AdsFlags({
    required this.enabled,
    required this.banner,
    required this.interstitial,
    required this.rewarded,
    required this.interstitialMinInterval,
    required this.rewardedUnlockDuration,
  });

  /// Tudo desligado. Usado sempre que os flags não puderam ser lidos: na dúvida, sem anúncios.
  static const off = AdsFlags(
    enabled: false,
    banner: false,
    interstitial: false,
    rewarded: false,
    interstitialMinInterval: Duration(minutes: 3),
    rewardedUnlockDuration: Duration(minutes: 60),
  );

  final bool enabled;
  final bool banner;
  final bool interstitial;
  final bool rewarded;
  final Duration interstitialMinInterval;
  final Duration rewardedUnlockDuration;

  factory AdsFlags.fromJson(Map<String, dynamic> json) => AdsFlags(
        enabled: json['enabled'] == true,
        banner: json['banner'] == true,
        interstitial: json['interstitial'] == true,
        rewarded: json['rewarded'] == true,
        interstitialMinInterval:
            Duration(seconds: (json['interstitialMinIntervalSeconds'] as num?)?.toInt() ?? 180),
        rewardedUnlockDuration:
            Duration(minutes: (json['rewardedUnlockMinutes'] as num?)?.toInt() ?? 60),
      );
}

class FeatureFlags {
  const FeatureFlags({required this.plano, required this.ads, this.manualSyncsPerDay});

  static const fallback = FeatureFlags(plano: 'simples', ads: AdsFlags.off);

  final String plano;
  final AdsFlags ads;

  /// Sincronizações manuais por dia no plano gratuito; `null` = ilimitado.
  final int? manualSyncsPerDay;

  factory FeatureFlags.fromJson(Map<String, dynamic> json) {
    final limits = json['limits'] as Map<String, dynamic>? ?? const {};
    return FeatureFlags(
      plano: json['plano'] as String? ?? 'simples',
      ads: AdsFlags.fromJson(json['ads'] as Map<String, dynamic>? ?? const {}),
      manualSyncsPerDay: (limits['manualSyncsPerDay'] as num?)?.toInt(),
    );
  }
}

class FeatureFlagsRepository {
  FeatureFlagsRepository(this._dio);

  final Dio _dio;

  Future<FeatureFlags> getMine() async {
    final response = await _dio.get('/users/me/features');
    return FeatureFlags.fromJson(response.data as Map<String, dynamic>);
  }
}

final featureFlagsRepositoryProvider = Provider<FeatureFlagsRepository>((ref) {
  return FeatureFlagsRepository(ref.watch(apiClientProvider).dio);
});

/// Flags do usuário logado. Qualquer falha (rede, 404 antes do cadastro, backend antigo sem o
/// endpoint) resolve para [FeatureFlags.fallback] — anúncios nunca aparecem "por engano".
/// Refeito a cada troca de usuário (login/logout), já que o plano é por usuário.
final featureFlagsProvider = FutureProvider<FeatureFlags>((ref) async {
  final uid = ref.watch(authStateProvider.select((s) => s.value?.uid));
  if (uid == null) return FeatureFlags.fallback;
  try {
    return await ref.watch(featureFlagsRepositoryProvider).getMine();
  } catch (_) {
    return FeatureFlags.fallback;
  }
});

/// Atalho síncrono para os widgets: enquanto os flags carregam, vale [AdsFlags.off].
final adsFlagsProvider = Provider<AdsFlags>((ref) {
  return ref.watch(featureFlagsProvider).maybeWhen(data: (f) => f.ads, orElse: () => AdsFlags.off);
});

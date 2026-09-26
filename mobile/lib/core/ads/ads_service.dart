import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_config.dart';
import 'ads_consent.dart';
import 'feature_flags.dart';
import 'frequency_cap.dart';

/// Ponto único de acesso ao AdMob no app: consentimento → inicialização do SDK → pré-carga e
/// exibição dos formatos de tela cheia. Os banners usam [adsReadyProvider] e cuidam do próprio
/// ciclo de vida em `SincroBannerAd`.
///
/// Onde anúncios NUNCA devem aparecer (decisão de produto, não técnica): Emergência, cards de
/// aterramento, jogos calmantes, alertas do Biofeedback e onboarding. Nenhuma dessas telas chama
/// este serviço — mantenha assim ao adicionar novos pontos de exibição.
class AdsService {
  AdsService();

  AdsFlags _flags = AdsFlags.off;
  final FrequencyCap _interstitialCap = FrequencyCap(minInterval: AdsFlags.off.interstitialMinInterval);

  Future<bool>? _initialization;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;

  AdsFlags get flags => _flags;

  void updateFlags(AdsFlags flags) {
    _flags = flags;
    _interstitialCap.minInterval = flags.interstitialMinInterval;
    if (!flags.interstitial) _disposeInterstitial();
    if (!flags.rewarded) _disposeRewarded();
  }

  /// Consentimento + `MobileAds.initialize()`, uma única vez por execução do app. Devolve se é
  /// permitido pedir anúncios. Só roda quando os flags ligam anúncios: quem nunca vai ver
  /// anúncios (ex.: plano pago) também nunca vê o formulário de consentimento.
  Future<bool> ensureInitialized() {
    if (!_flags.enabled || !adsSupportedPlatform) return Future.value(false);
    return _initialization ??= _initialize();
  }

  Future<bool> _initialize() async {
    try {
      final canRequest = await AdsConsent.gather();
      if (!canRequest) return false;
      await MobileAds.instance.initialize();
      _preloadInterstitial();
      _preloadRewarded();
      return true;
    } catch (e) {
      debugPrint('Falha ao inicializar anúncios: $e');
      _initialization = null; // permite nova tentativa na próxima tela
      return false;
    }
  }

  // ---------------------------------------------------------------- Intersticial

  void _preloadInterstitial() {
    final unitId = adUnitIdFor(AdFormat.interstitial);
    if (!_flags.interstitial || unitId == null || _interstitial != null || _loadingInterstitial) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
          debugPrint('Intersticial não carregou: ${error.message}');
        },
      ),
    );
  }

  /// Mostra o intersticial depois de uma ação concluída com sucesso — se os flags permitirem, se
  /// já houver um anúncio pré-carregado e se o último foi exibido há mais de
  /// `interstitialMinInterval` (3 min por padrão). Nunca espera o carregamento: se não estiver
  /// pronto, a pessoa segue sem anúncio e o próximo é pré-carregado em segundo plano.
  Future<bool> maybeShowInterstitial() async {
    if (!_flags.interstitial || !_interstitialCap.canShow) return false;
    if (!await ensureInitialized()) return false;
    final ad = _interstitial;
    if (ad == null) {
      _preloadInterstitial();
      return false;
    }
    _interstitial = null;
    final dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        dismissed.complete();
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
        _preloadInterstitial();
      },
    );
    _interstitialCap.markShown();
    await ad.show();
    await dismissed.future;
    return true;
  }

  // ---------------------------------------------------------------- Premiado

  void _preloadRewarded() {
    final unitId = adUnitIdFor(AdFormat.rewarded);
    if (!_flags.rewarded || unitId == null || _rewarded != null || _loadingRewarded) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingRewarded = false;
          _rewarded = ad;
        },
        onAdFailedToLoad: (error) {
          _loadingRewarded = false;
          debugPrint('Premiado não carregou: ${error.message}');
        },
      ),
    );
  }

  /// Se há um anúncio premiado pronto para ser oferecido. A UI só mostra o botão "Assistir
  /// vídeo" quando `true` — nunca prometa uma recompensa que não pode entregar.
  bool get rewardedReady => _flags.rewarded && _rewarded != null;

  /// Exibe o premiado e devolve `true` só se a pessoa assistiu até ganhar a recompensa.
  Future<bool> showRewarded() async {
    if (!_flags.rewarded || !await ensureInitialized()) return false;
    final ad = _rewarded;
    if (ad == null) {
      _preloadRewarded();
      return false;
    }
    _rewarded = null;
    var earned = false;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        closed.complete();
        _preloadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
        _preloadRewarded();
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    await closed.future;
    return earned;
  }

  void _disposeInterstitial() {
    _interstitial?.dispose();
    _interstitial = null;
  }

  void _disposeRewarded() {
    _rewarded?.dispose();
    _rewarded = null;
  }

  void dispose() {
    _disposeInterstitial();
    _disposeRewarded();
  }
}

final adsServiceProvider = Provider<AdsService>((ref) {
  final service = AdsService();
  service.updateFlags(ref.read(adsFlagsProvider));
  ref.listen<AdsFlags>(adsFlagsProvider, (_, next) => service.updateFlags(next));
  ref.onDispose(service.dispose);
  return service;
});

/// `true` quando o SDK está pronto e o consentimento permite pedir anúncios. Reavaliado quando os
/// flags mudam (ex.: login de outro usuário, troca de plano).
final adsReadyProvider = FutureProvider<bool>((ref) {
  final flags = ref.watch(adsFlagsProvider);
  final service = ref.watch(adsServiceProvider);
  service.updateFlags(flags);
  return service.ensureInitialized();
});

/// Se Configurações deve mostrar "Privacidade dos anúncios" (entrada obrigatória para rever o
/// consentimento quando o UMP exige, ex.: usuários na UE).
final adsPrivacyOptionsRequiredProvider = FutureProvider<bool>((ref) async {
  if (!await ref.watch(adsReadyProvider.future)) return false;
  return AdsConsent.privacyOptionsRequired();
});

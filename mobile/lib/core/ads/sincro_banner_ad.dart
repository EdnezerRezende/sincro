import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_config.dart';
import 'ads_service.dart';
import 'feature_flags.dart';

/// Banner adaptativo ancorado para o rodapé de telas de listagem/consulta. Use como
/// `Scaffold(bottomNavigationBar: const SincroBannerAd())`.
///
/// Controlado pelo feature toggle `ads.banner` (backend): desligado, sem consentimento, em
/// plataforma sem suporte ou se o anúncio falhar, o widget ocupa **zero pixels** — a tela fica
/// exatamente como era antes dos anúncios.
class SincroBannerAd extends ConsumerWidget {
  const SincroBannerAd({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bannerOn = ref.watch(adsFlagsProvider.select((f) => f.banner));
    if (!bannerOn || adUnitIdFor(AdFormat.banner) == null) return const SizedBox.shrink();
    final ready = ref.watch(adsReadyProvider).value ?? false;
    if (!ready) return const SizedBox.shrink();
    return const _AdaptiveBanner();
  }
}

class _AdaptiveBanner extends StatefulWidget {
  const _AdaptiveBanner();

  @override
  State<_AdaptiveBanner> createState() => _AdaptiveBannerState();
}

class _AdaptiveBannerState extends State<_AdaptiveBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _loadedForWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A largura só é conhecida com o MediaQuery; recarrega se mudar (ex.: rotação).
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width != _loadedForWidth) _load(width);
  }

  Future<void> _load(int width) async {
    _loadedForWidth = width;
    final unitId = adUnitIdFor(AdFormat.banner);
    if (unitId == null) return;
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;

    await _ad?.dispose();
    final ad = BannerAd(
      adUnitId: unitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _loaded = false);
        },
      ),
    );
    setState(() {
      _ad = ad;
      _loaded = false;
    });
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: ad.size.height.toDouble(),
          child: Center(
            child: SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        ),
      ),
    );
  }
}

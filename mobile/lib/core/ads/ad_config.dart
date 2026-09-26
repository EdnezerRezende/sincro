import 'dart:io';

import 'package:flutter/foundation.dart';

/// IDs dos blocos de anúncio (Ad Units) do AdMob.
///
/// Build de release usa os blocos reais da conta AdMob do Sincro ([_prodIds]); debug/profile usa
/// os IDs de teste oficiais do Google — nunca clique em anúncios reais durante o desenvolvimento
/// (risco de suspensão da conta). Um `--dart-define=ADMOB_<FORMATO>_<PLATAFORMA>=...` sobrescreve
/// ambos (ex.: para testar um bloco novo sem mudar o código). Ad Unit IDs não são segredos: vão
/// embutidos no app publicado.
enum AdFormat { banner, interstitial, rewarded }

/// Blocos reais (AdMob → Apps → Sincro → Blocos de anúncios).
/// App IDs: Android ca-app-pub-8203324650722374~1392959320 · iOS ca-app-pub-8203324650722374~6578012408
/// (configurados em android/app/build.gradle.kts e ios/Flutter/*.xcconfig).
const _prodIds = {
  AdFormat.banner: (android: 'ca-app-pub-8203324650722374/5140632641', ios: 'ca-app-pub-8203324650722374/8429226687'),
  AdFormat.interstitial: (android: 'ca-app-pub-8203324650722374/3827550970', ios: 'ca-app-pub-8203324650722374/1409446208'),
  AdFormat.rewarded: (android: 'ca-app-pub-8203324650722374/2490504299', ios: 'ca-app-pub-8203324650722374/7575224298'),
};

/// IDs de teste públicos do Google (https://developers.google.com/admob/flutter/test-ads).
const _testIds = {
  AdFormat.banner: (android: 'ca-app-pub-3940256099942544/9214589741', ios: 'ca-app-pub-3940256099942544/2435281174'),
  AdFormat.interstitial: (android: 'ca-app-pub-3940256099942544/1033173712', ios: 'ca-app-pub-3940256099942544/4411468910'),
  AdFormat.rewarded: (android: 'ca-app-pub-3940256099942544/5224354917', ios: 'ca-app-pub-3940256099942544/1712485313'),
};

const _definedIds = {
  AdFormat.banner: (
    android: String.fromEnvironment('ADMOB_BANNER_ANDROID'),
    ios: String.fromEnvironment('ADMOB_BANNER_IOS'),
  ),
  AdFormat.interstitial: (
    android: String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID'),
    ios: String.fromEnvironment('ADMOB_INTERSTITIAL_IOS'),
  ),
  AdFormat.rewarded: (
    android: String.fromEnvironment('ADMOB_REWARDED_ANDROID'),
    ios: String.fromEnvironment('ADMOB_REWARDED_IOS'),
  ),
};

/// Anúncios só existem no app nativo: o plugin não tem implementação web nem desktop.
bool get adsSupportedPlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Devolve o Ad Unit ID do [format] para a plataforma atual, ou `null` em plataforma sem suporte.
String? adUnitIdFor(AdFormat format) {
  if (!adsSupportedPlatform) return null;
  final defined = Platform.isAndroid ? _definedIds[format]!.android : _definedIds[format]!.ios;
  if (defined.isNotEmpty) return defined;
  final ids = kReleaseMode ? _prodIds[format]! : _testIds[format]!;
  return Platform.isAndroid ? ids.android : ids.ios;
}

/// Hash do aparelho de teste para o UMP forçar o formulário de consentimento como se estivesse
/// na UE (aparece no logcat/console na primeira execução). Só usado fora de release.
const umpTestDeviceId = String.fromEnvironment('UMP_TEST_DEVICE_ID');

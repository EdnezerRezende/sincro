import 'dart:io';

import 'package:flutter/foundation.dart';

/// IDs dos blocos de anúncio (Ad Units) do AdMob.
///
/// Os IDs reais entram por `--dart-define` no build de release (ver `mobile/README.md`, seção
/// "Anúncios (AdMob)"). Em debug/profile, sem o define, caímos nos IDs de teste oficiais do
/// Google — nunca clique em anúncios reais durante o desenvolvimento (risco de suspensão da conta).
/// Em release, sem o define, o formato fica simplesmente desligado: melhor não mostrar nada do que
/// publicar um app servindo anúncios de teste.
enum AdFormat { banner, interstitial, rewarded }

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

/// Devolve o Ad Unit ID do [format] para a plataforma atual, ou `null` quando o formato não deve
/// ser carregado (plataforma sem suporte ou release sem ID real configurado).
String? adUnitIdFor(AdFormat format) {
  if (!adsSupportedPlatform) return null;
  final defined = Platform.isAndroid ? _definedIds[format]!.android : _definedIds[format]!.ios;
  if (defined.isNotEmpty) return defined;
  if (kReleaseMode) return null;
  return Platform.isAndroid ? _testIds[format]!.android : _testIds[format]!.ios;
}

/// Hash do aparelho de teste para o UMP forçar o formulário de consentimento como se estivesse
/// na UE (aparece no logcat/console na primeira execução). Só usado fora de release.
const umpTestDeviceId = String.fromEnvironment('UMP_TEST_DEVICE_ID');

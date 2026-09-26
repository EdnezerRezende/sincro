import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_config.dart';

/// Fluxo de consentimento (UMP — User Messaging Platform) exigido pela Google antes de pedir
/// anúncios: GDPR/UE+UK, leis estaduais dos EUA e, via mensagem de IDFA, o ATT do iOS. As
/// mensagens em si são configuradas no painel do AdMob (Privacidade e mensagens); aqui só as
/// pedimos e exibimos.
class AdsConsent {
  AdsConsent._();

  /// Atualiza o status de consentimento e, se a região do usuário exigir, mostra o formulário.
  /// Devolve se já é permitido pedir anúncios. Nunca lança: erro do UMP = sem anúncios agora.
  static Future<bool> gather() async {
    final debugSettings = !kReleaseMode && umpTestDeviceId.isNotEmpty
        ? ConsentDebugSettings(
            debugGeography: DebugGeography.debugGeographyEea,
            testIdentifiers: [umpTestDeviceId],
          )
        : null;

    final updated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(consentDebugSettings: debugSettings),
      () => updated.complete(),
      (error) {
        debugPrint('UMP requestConsentInfoUpdate falhou: ${error.message}');
        updated.complete();
      },
    );
    await updated.future;

    final formDone = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error != null) debugPrint('UMP formulário falhou: ${error.message}');
      formDone.complete();
    });
    await formDone.future;

    return ConsentInformation.instance.canRequestAds();
  }

  /// Se o usuário precisa de um ponto de entrada permanente para rever a escolha (obrigatório
  /// na UE). A tela de Configurações mostra o item "Privacidade dos anúncios" quando `true`.
  static Future<bool> privacyOptionsRequired() async {
    if (!adsSupportedPlatform) return false;
    final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
    return status == PrivacyOptionsRequirementStatus.required;
  }

  static Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) debugPrint('UMP opções de privacidade falhou: ${error.message}');
      done.complete();
    });
    await done.future;
  }
}

# sincro_mobile

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Gmail email triage feature (requires a dart-define)

The "Conectar Gmail" flow on the Home screen requires a Google OAuth Web Client ID to be passed
at build/run time via `--dart-define=GOOGLE_WEB_CLIENT_ID=...`. Without it, Android's native
Google Sign-In flow silently returns a null `serverAuthCode`, the connection request throws, and
the user only sees a generic "Não foi possível conectar" message with no indication why.

```
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=your-client-id.apps.googleusercontent.com
```

Use the same OAuth Web Client ID configured on the backend (`GOOGLE_CLIENT_ID` in
`backend/.env`) — see the Prerequisites section of
`docs/superpowers/plans/2026-08-02-gestao-executiva-triagem-email-plan.md` for how to create one.

## Biofeedback (HealthKit / Health Connect)

The Biofeedback pillar reads heart-rate and HRV data on-device via the `health` package. It needs
some platform setup that a Dart diff can't fully capture:

- **iOS — HealthKit capability (manual Xcode step).** Open `ios/Runner.xcworkspace` in Xcode,
  select the *Runner* target → *Signing & Capabilities* → *+ Capability* → **HealthKit**. Without
  it the app can't read HealthKit and permission requests fail at runtime. `Info.plist` already
  carries `NSHealthShareUsageDescription`, plus `BGTaskSchedulerPermittedIdentifiers`
  (`biofeedback-sync`) and `UIBackgroundModes` for the background refresh — keep the identifier in
  sync with `biofeedbackTaskName` in
  `lib/features/biofeedback/biofeedback_background_task.dart`.
- **Android — `minSdk 26`.** `android/app/build.gradle.kts` pins `minSdk = 26` because the
  `health` library declares `minSdkVersion 26`; going back to Flutter's default (21) fails the
  manifest merge. `MainActivity` must stay a `FlutterFragmentActivity` (Health Connect launches
  its permission sheet through `registerForActivityResult`), and `AndroidManifest.xml` carries the
  `<queries>` block plus the `ViewPermissionUsageActivity` alias required by Health Connect.
- **`dependency_overrides` in `pubspec.yaml`.** `workmanager_platform_interface` and
  `workmanager_android` are pinned there to keep `workmanager` compiling on this project's Flutter
  SDK. Re-verify (and ideally drop the overrides) whenever the Flutter SDK is bumped to
  >= 3.38.0 or `workmanager` is upgraded — the block's own comment explains the exact conflict.

## Anúncios (AdMob) — versão gratuita

Código em `lib/core/ads/`. Tudo começa **desligado**: quem decide se anúncios aparecem é o backend,
via `GET /users/me/features` (`backend/src/users/feature-flags.ts`), combinando as variáveis
`ADS_*` do `.env` com o `plano` do usuário (planos em `ADS_FREE_PLANS` nunca veem anúncios).

| Formato | Onde | Regra |
|---|---|---|
| Banner adaptativo ancorado | rodapé de Caixa de Entrada, Finanças, Calendário (`SincroBannerAd`) | toggle `ads.banner`; desligado/falhou = 0 px |
| Intersticial | após "Sincronização concluída" na Caixa de Entrada | toggle `ads.interstitial`; no máx. 1 a cada `ADS_INTERSTITIAL_MIN_INTERVAL_SECONDS` (180) |
| Premiado | quando a cota `FREE_MANUAL_SYNCS_PER_DAY` acaba | toggle `ads.rewarded`; libera sincronizações ilimitadas por `ADS_REWARDED_UNLOCK_MINUTES` |

**Nunca** exibir anúncios em Emergência, cards de aterramento, jogos calmantes, Biofeedback,
busca de profissionais ou onboarding.

### IDs

Já estão no código: nenhum parâmetro extra de build é necessário.

| | Android | iOS |
|---|---|---|
| App ID | `ca-app-pub-8203324650722374~1392959320` | `ca-app-pub-8203324650722374~6578012408` |
| Banner | `ca-app-pub-8203324650722374/5140632641` | `ca-app-pub-8203324650722374/8429226687` |
| Intersticial | `ca-app-pub-8203324650722374/3827550970` | `ca-app-pub-8203324650722374/1409446208` |
| Premiado | `ca-app-pub-8203324650722374/2490504299` | `ca-app-pub-8203324650722374/7575224298` |

- Blocos: `lib/core/ads/ad_config.dart`. **Release** usa os blocos reais; **debug/profile** usa os
  blocos de teste do Google (nunca clique nos anúncios reais). `--dart-define=ADMOB_BANNER_ANDROID=...`
  (e equivalentes `_INTERSTITIAL_`, `_REWARDED_`, `_IOS`) sobrescreve os dois.
- App ID Android: `android/app/build.gradle.kts` (sobrescrevível por `ADMOB_APP_ID_ANDROID` no
  ambiente ou `admobAppId=` em `android/key.properties`).
- App ID iOS: `ios/Flutter/Debug.xcconfig` e `Release.xcconfig` (sobrescrevível por
  `ios/Flutter/AdMob.xcconfig`, fora do git).

### Consentimento (UMP)

As mensagens (GDPR, leis estaduais dos EUA, IDFA/ATT) são criadas no AdMob em **Privacidade e
mensagens**; o app só as exibe (`AdsConsent.gather()`) antes de inicializar o SDK. Quando o UMP
exige, Configurações → Conta mostra "Privacidade dos anúncios". Para testar como usuário da UE,
rode com `--dart-define=UMP_TEST_DEVICE_ID=<hash do logcat/console>`.

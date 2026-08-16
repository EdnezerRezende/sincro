import 'package:shared_preferences/shared_preferences.dart';

const _chaveVersaoVista = 'guide_last_seen_version';

/// Preferência local, mesmo padrão de `BiofeedbackCache`/`HomeLayoutPreference`: não sincroniza
/// entre aparelhos nem passa pelo backend, só controla o que este dispositivo já viu.
class GuidePreference {
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  /// `0` quando nada foi salvo: cobre tanto quem nunca abriu o app quanto uma reinstalação —
  /// nesses casos o guia completo deve aparecer.
  Future<int> getVersaoVista() async {
    return await _prefs.getInt(_chaveVersaoVista) ?? 0;
  }

  Future<void> setVersaoVista(int versao) {
    return _prefs.setInt(_chaveVersaoVista, versao);
  }
}

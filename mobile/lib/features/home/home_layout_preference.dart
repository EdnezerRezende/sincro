import 'package:shared_preferences/shared_preferences.dart';
import 'home_layout_mode.dart';
import 'home_design_style.dart';

const _chaveModo = 'home_layout_mode';
const _chaveDesign = 'home_design_style';

/// Preferência de exibição, não dado de negócio — fica só no dispositivo, mesmo padrão local de
/// `BiofeedbackCache` (não precisa sincronizar entre aparelhos nem passar pelo backend).
class HomeLayoutPreference {
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  /// `resumo` é o padrão: menor volume de informação simultânea, mais seguro para quem acabou
  /// de instalar o app e ainda não sabe do que precisa.
  Future<HomeLayoutMode> getModo() async {
    final raw = await _prefs.getString(_chaveModo);
    return HomeLayoutMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => HomeLayoutMode.resumo,
    );
  }

  Future<void> setModo(HomeLayoutMode modo) {
    return _prefs.setString(_chaveModo, modo.name);
  }

  /// `minimalista` é o padrão: elegância refinada com espaçamento generoso.
  Future<HomeDesignStyle> getDesign() async {
    final raw = await _prefs.getString(_chaveDesign);
    return HomeDesignStyle.values.firstWhere(
      (d) => d.name == raw,
      orElse: () => HomeDesignStyle.minimalista,
    );
  }

  Future<void> setDesign(HomeDesignStyle design) {
    return _prefs.setString(_chaveDesign, design.name);
  }
}

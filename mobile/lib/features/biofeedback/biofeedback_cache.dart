import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'biofeedback_summary.dart';
import 'dia_repouso.dart';

const _chaveAtivo = 'biofeedback_ativo';
const _chaveFrequenciaMinutos = 'biofeedback_frequencia_minutos';
const _chaveResumo = 'biofeedback_resumo';
const _chaveHistoricoRepouso = 'biofeedback_historico_repouso';
const _frequenciaPadraoMinutos = 30;

class BiofeedbackCache {
  /// `SharedPreferencesAsync` — e não a API legada `SharedPreferences.getInstance()` — porque a
  /// sincronização em background roda em um isolate separado. A API legada mantém um cache em
  /// memória por isolate, preenchido uma única vez: o isolate principal nunca enxergaria o resumo
  /// gravado pelo isolate do background e o app continuaria mostrando dados velhos. Esta API não
  /// cacheia nada em memória, sempre lê do armazenamento nativo.
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  Future<bool> isAtivo() async {
    return await _prefs.getBool(_chaveAtivo) ?? false;
  }

  Future<void> setAtivo(bool ativo) {
    return _prefs.setBool(_chaveAtivo, ativo);
  }

  Future<int> getFrequenciaMinutos() async {
    return await _prefs.getInt(_chaveFrequenciaMinutos) ?? _frequenciaPadraoMinutos;
  }

  Future<void> setFrequenciaMinutos(int minutos) {
    return _prefs.setInt(_chaveFrequenciaMinutos, minutos);
  }

  Future<BiofeedbackSummary?> getResumo() async {
    final raw = await _prefs.getString(_chaveResumo);
    if (raw == null) return null;
    return BiofeedbackSummary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setResumo(BiofeedbackSummary resumo) {
    return _prefs.setString(_chaveResumo, jsonEncode(resumo.toJson()));
  }

  Future<List<DiaRepouso>> getHistoricoRepouso() async {
    final raw = await _prefs.getString(_chaveHistoricoRepouso);
    if (raw == null) return [];
    final lista = jsonDecode(raw) as List<dynamic>;
    return lista.map((e) => DiaRepouso.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setHistoricoRepouso(List<DiaRepouso> historico) {
    final lista = historico.map((d) => d.toJson()).toList();
    return _prefs.setString(_chaveHistoricoRepouso, jsonEncode(lista));
  }

  Future<void> clear() async {
    await _prefs.remove(_chaveAtivo);
    await _prefs.remove(_chaveFrequenciaMinutos);
    await _prefs.remove(_chaveResumo);
    await _prefs.remove(_chaveHistoricoRepouso);
  }
}

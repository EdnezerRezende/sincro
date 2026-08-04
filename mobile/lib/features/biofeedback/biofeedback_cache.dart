import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'biofeedback_summary.dart';
import 'dia_repouso.dart';

const _chaveAtivo = 'biofeedback_ativo';
const _chaveFrequenciaMinutos = 'biofeedback_frequencia_minutos';
const _chaveResumo = 'biofeedback_resumo';
const _chaveHistoricoRepouso = 'biofeedback_historico_repouso';
const _chavePermissoesVersao = 'biofeedback_permissoes_versao';
const _frequenciaPadraoMinutos = 30;

class BiofeedbackCache {
  /// Versão do conjunto de permissões de saúde que o app precisa hoje.
  ///
  /// 1 = Fase 1 (frequência cardíaca + variabilidade).
  /// 2 = Fase 2 (as duas acima + passos + treinos, usadas para filtrar leituras fora de repouso).
  ///
  /// A permissão só é pedida na ativação do Biofeedback, então quem ativou na Fase 1 nunca seria
  /// perguntado de novo. Guardar a versão concedida permite pedir a diferença uma única vez.
  static const versaoPermissoesAtual = 2;

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

  /// `0` quando nada foi gravado: é o caso de quem ativou o Biofeedback na Fase 1, antes de esta
  /// chave existir, e por isso concedeu apenas as permissões daquela versão.
  Future<int> getPermissoesVersao() async {
    return await _prefs.getInt(_chavePermissoesVersao) ?? 0;
  }

  Future<void> setPermissoesVersao(int versao) {
    return _prefs.setInt(_chavePermissoesVersao, versao);
  }

  Future<void> clear() async {
    await _prefs.remove(_chaveAtivo);
    await _prefs.remove(_chaveFrequenciaMinutos);
    await _prefs.remove(_chaveResumo);
    await _prefs.remove(_chaveHistoricoRepouso);
    await _prefs.remove(_chavePermissoesVersao);
  }
}

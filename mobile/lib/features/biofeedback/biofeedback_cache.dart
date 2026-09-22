import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'biofeedback_summary.dart';
import 'dia_repouso.dart';
import 'serie_dia.dart';

const _chaveAtivo = 'biofeedback_ativo';
const _chaveFrequenciaMinutos = 'biofeedback_frequencia_minutos';
// v2: `mediaFcHoje`/`mediaVfcHoje` passaram a guardar a média filtrada por repouso (a mesma que
// decide `estadoEstresse`), não mais a média bruta do dia inteiro. Trocar a chave faz um resumo
// gravado pela versão antiga do app ser tratado como ausente (`getResumo` volta `null`) em vez de
// ser lido e exibido sob o rótulo novo com o valor antigo — que seria exatamente a incoerência que
// essa mudança existe para eliminar.
// v3: novos campos (última leitura com horário, FC em repouso nativa, mín/máx, linha de base). Os
// campos são opcionais no JSON, mas a chave sobe mesmo assim para que o resumo v2 não seja mostrado
// com os novos tiles vazios até a próxima sincronização.
const _chaveResumo = 'biofeedback_resumo_v3';
const _chaveSerieDia = 'biofeedback_serie_dia';
const _chaveUltimoPreenchimento = 'biofeedback_historico_preenchido_em';
const _chaveHistoricoRepouso = 'biofeedback_historico_repouso';
const _chavePermissoesVersao = 'biofeedback_permissoes_versao';
const _chaveAlertasAtivos = 'biofeedback_alertas_ativos';
const _frequenciaPadraoMinutos = 30;

class BiofeedbackCache {
  /// Versão do conjunto de permissões de saúde que o app precisa hoje.
  ///
  /// 1 = Fase 1 (frequência cardíaca + variabilidade).
  /// 2 = Fase 2 (as duas acima + passos + treinos, usadas para filtrar leituras fora de repouso).
  /// 3 = frequência cardíaca em repouso calculada pela plataforma (a mesma que o relógio mostra).
  ///
  /// A permissão só é pedida na ativação do Biofeedback, então quem ativou na Fase 1 nunca seria
  /// perguntado de novo. Guardar a versão concedida permite pedir a diferença uma única vez.
  static const versaoPermissoesAtual = 3;

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

  /// Valor ilegível (cache corrompido ou de outra versão) vale como "sem série": um gráfico vazio
  /// até a próxima sincronização é bem melhor do que derrubar a tela ou a sincronização inteira.
  Future<SerieDia?> getSerieDia() async {
    final raw = await _prefs.getString(_chaveSerieDia);
    if (raw == null) return null;
    try {
      return SerieDia.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> setSerieDia(SerieDia serie) {
    return _prefs.setString(_chaveSerieDia, jsonEncode(serie.toJson()));
  }

  /// Instante do último preenchimento retroativo do histórico a partir da plataforma de saúde
  /// (ver `BiofeedbackSyncService`). `null` quando nunca rodou.
  Future<DateTime?> getUltimoPreenchimento() async {
    final raw = await _prefs.getString(_chaveUltimoPreenchimento);
    // Valor ilegível vale como "nunca rodou" — o preenchimento é refeito, nunca a sincronização
    // inteira derrubada por uma preferência corrompida.
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setUltimoPreenchimento(DateTime quando) {
    return _prefs.setString(_chaveUltimoPreenchimento, quando.toIso8601String());
  }

  /// `0` quando nada foi gravado: é o caso de quem ativou o Biofeedback na Fase 1, antes de esta
  /// chave existir, e por isso concedeu apenas as permissões daquela versão.
  Future<int> getPermissoesVersao() async {
    return await _prefs.getInt(_chavePermissoesVersao) ?? 0;
  }

  Future<void> setPermissoesVersao(int versao) {
    return _prefs.setInt(_chavePermissoesVersao, versao);
  }

  Future<bool> getAlertasAtivos() async {
    return await _prefs.getBool(_chaveAlertasAtivos) ?? true;
  }

  Future<void> setAlertasAtivos(bool ativos) {
    return _prefs.setBool(_chaveAlertasAtivos, ativos);
  }

  Future<void> clear() async {
    await _prefs.remove(_chaveAtivo);
    await _prefs.remove(_chaveFrequenciaMinutos);
    await _prefs.remove(_chaveResumo);
    await _prefs.remove(_chaveHistoricoRepouso);
    await _prefs.remove(_chavePermissoesVersao);
    await _prefs.remove(_chaveAlertasAtivos);
    await _prefs.remove(_chaveSerieDia);
    await _prefs.remove(_chaveUltimoPreenchimento);
  }
}

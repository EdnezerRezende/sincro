import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'biofeedback_summary.dart';

const _chaveAtivo = 'biofeedback_ativo';
const _chaveFrequenciaMinutos = 'biofeedback_frequencia_minutos';
const _chaveResumo = 'biofeedback_resumo';
const _frequenciaPadraoMinutos = 30;

class BiofeedbackCache {
  Future<bool> isAtivo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_chaveAtivo) ?? false;
  }

  Future<void> setAtivo(bool ativo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chaveAtivo, ativo);
  }

  Future<int> getFrequenciaMinutos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_chaveFrequenciaMinutos) ?? _frequenciaPadraoMinutos;
  }

  Future<void> setFrequenciaMinutos(int minutos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chaveFrequenciaMinutos, minutos);
  }

  Future<BiofeedbackSummary?> getResumo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chaveResumo);
    if (raw == null) return null;
    return BiofeedbackSummary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setResumo(BiofeedbackSummary resumo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveResumo, jsonEncode(resumo.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chaveAtivo);
    await prefs.remove(_chaveFrequenciaMinutos);
    await prefs.remove(_chaveResumo);
  }
}

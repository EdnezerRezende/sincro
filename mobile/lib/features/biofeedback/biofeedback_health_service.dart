import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:health/health.dart';
import 'health_reading.dart';
import 'treino_intervalo.dart';

/// Métrica de variabilidade cardíaca disponível em cada plataforma: o HealthKit expõe SDNN e o
/// Health Connect expõe RMSSD (o `health` não oferece SDNN no Android, e a permissão declarada no
/// AndroidManifest, `READ_HEART_RATE_VARIABILITY`, é justamente a de RMSSD). SDNN e RMSSD são
/// métricas diferentes e não são diretamente comparáveis entre si; aqui as duas são tratadas
/// simplesmente como "vfc" em milissegundos, o que é aceitável porque o app só mostra um resumo
/// calmo do próprio usuário, sem comparar um aparelho com o outro.
///
/// `!kIsWeb &&` vem antes por curto-circuito: `Platform.isIOS` lança em runtime no Flutter Web
/// (mesmo caso do guard em main.dart). O plugin `health` não é suportado no web de qualquer forma,
/// então o valor RMSSD aqui é só para nunca crashar — nunca é de fato usado nessa plataforma.
HealthDataType get _tipoVfc => !kIsWeb && Platform.isIOS
    ? HealthDataType.HEART_RATE_VARIABILITY_SDNN
    : HealthDataType.HEART_RATE_VARIABILITY_RMSSD;

class BiofeedbackHealthService {
  final Health _health = Health();

  Future<void>? _configuracao;

  /// `configure()` precisa rodar uma vez antes de qualquer uso do plugin. O Future é guardado
  /// para que chamadas concorrentes compartilhem a mesma configuração em vez de repeti-la.
  Future<void> _garantirConfigurado() => _configuracao ??= _health.configure();

  List<HealthDataType> get _tipos =>
      [HealthDataType.HEART_RATE, _tipoVfc, HealthDataType.STEPS, HealthDataType.WORKOUT];

  Future<bool> solicitarPermissao() async {
    await _garantirConfigurado();
    final tipos = _tipos;
    return _health.requestAuthorization(
      tipos,
      permissions: tipos.map((_) => HealthDataAccess.READ).toList(),
    );
  }

  Future<List<HealthReading>> lerFrequenciaCardiacaHoje() {
    return _lerTipoHoje(HealthDataType.HEART_RATE);
  }

  Future<List<HealthReading>> lerVariabilidadeHoje() {
    return _lerTipoHoje(_tipoVfc);
  }

  Future<List<HealthReading>> lerPassosHoje() {
    return _lerTipoHoje(HealthDataType.STEPS);
  }

  Future<List<TreinoIntervalo>> lerTreinosHoje() async {
    await _garantirConfigurado();
    final agora = DateTime.now();
    final inicioDoDia = DateTime(agora.year, agora.month, agora.day);
    final pontos = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WORKOUT],
      startTime: inicioDoDia,
      endTime: agora,
    );
    return pontos
        .map((p) => TreinoIntervalo(inicio: p.dateFrom, fim: p.dateTo))
        .toList();
  }

  Future<List<HealthReading>> _lerTipoHoje(HealthDataType tipo) async {
    await _garantirConfigurado();
    final agora = DateTime.now();
    final inicioDoDia = DateTime(agora.year, agora.month, agora.day);
    final pontos = await _health.getHealthDataFromTypes(
      types: [tipo],
      startTime: inicioDoDia,
      endTime: agora,
    );
    return pontos
        .map(
          (p) => HealthReading(
            valor: (p.value as NumericHealthValue).numericValue.toDouble(),
            timestamp: p.dateFrom,
          ),
        )
        .toList();
  }
}

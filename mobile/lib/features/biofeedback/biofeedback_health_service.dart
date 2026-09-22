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

/// Tempo máximo tolerado para uma chamada ao plugin `health`. Sem isso, um relógio lento para
/// sincronizar ou um Health Connect ocupado pode deixar a chamada pendurada indefinidamente — a
/// tela de Biofeedback ficaria "carregando" para sempre, sem cair nem no caminho de sucesso nem
/// no de erro.
const _timeoutLeitura = Duration(seconds: 15);

/// Intervalo de tempo [inicio, fim) de uma leitura.
typedef Periodo = ({DateTime inicio, DateTime fim});

class BiofeedbackHealthService {
  final Health _health = Health();

  Future<void>? _configuracao;

  /// `configure()` precisa rodar uma vez antes de qualquer uso do plugin. O Future é guardado
  /// para que chamadas concorrentes compartilhem a mesma configuração em vez de repeti-la.
  Future<void> _garantirConfigurado() => _configuracao ??= _health.configure();

  /// Tipos sem os quais o Biofeedback não funciona — é este conjunto que decide se a tela mostra
  /// a parede "Conceder acesso".
  List<HealthDataType> get _tiposEssenciais => [
        HealthDataType.HEART_RATE,
        _tipoVfc,
        HealthDataType.STEPS,
        HealthDataType.WORKOUT,
      ];

  /// `RESTING_HEART_RATE` é a frequência em repouso que a própria plataforma calcula (a mesma que
  /// o relógio mostra). Foi acrescentada na versão 3 das permissões — ver
  /// `BiofeedbackCache.versaoPermissoesAtual`. É pedida junto com as demais, mas é um extra: no
  /// Android `hasPermissions` é tudo-ou-nada, então quem desmarcar só esse tipo não pode ser
  /// tratado como "sem acesso" — por isso ela fica fora de [_tiposEssenciais].
  List<HealthDataType> get _tipos => [..._tiposEssenciais, HealthDataType.RESTING_HEART_RATE];

  Future<bool> solicitarPermissao() async {
    await _garantirConfigurado();
    final tipos = _tipos;
    return _health.requestAuthorization(
      tipos,
      permissions: tipos.map((_) => HealthDataAccess.READ).toList(),
    );
  }

  /// `null` quando a plataforma não informa o estado com confiança — o HealthKit no iOS pode
  /// devolver isso por design mesmo com a permissão concedida. Quem chama deve tratar `null` como
  /// "desconhecido", nunca como "negado".
  Future<bool?> verificarPermissao() async {
    await _garantirConfigurado();
    final tipos = _tiposEssenciais;
    return _health.hasPermissions(
      tipos,
      permissions: tipos.map((_) => HealthDataAccess.READ).toList(),
    );
  }

  /// Período de hoje: da meia-noite local até agora. (Construtor de calendário, não `Duration`:
  /// em dia de horário de verão o dia não tem 24 h.)
  static Periodo hoje([DateTime? agora]) {
    final fim = agora ?? DateTime.now();
    return (inicio: DateTime(fim.year, fim.month, fim.day), fim: fim);
  }

  Future<List<HealthReading>> lerFrequenciaCardiacaHoje() =>
      lerFrequenciaCardiaca(hoje());

  Future<List<HealthReading>> lerVariabilidadeHoje() => lerVariabilidade(hoje());

  Future<List<HealthReading>> lerPassosHoje() => lerPassos(hoje());

  Future<List<TreinoIntervalo>> lerTreinosHoje() => lerTreinos(hoje());

  Future<List<HealthReading>> lerFrequenciaCardiaca(Periodo periodo) =>
      _lerTipo(HealthDataType.HEART_RATE, periodo);

  Future<List<HealthReading>> lerVariabilidade(Periodo periodo) => _lerTipo(_tipoVfc, periodo);

  Future<List<HealthReading>> lerPassos(Periodo periodo) =>
      _lerTipo(HealthDataType.STEPS, periodo);

  /// Frequência cardíaca em repouso calculada pela plataforma (uma amostra por dia, em geral).
  /// A leitura mais recente dentro do período é a que o relógio está mostrando — pode ser a de
  /// ontem, se a de hoje ainda não foi calculada.
  Future<HealthReading?> lerFrequenciaRepousoNativa(Periodo periodo) async {
    final leituras = await _lerTipo(HealthDataType.RESTING_HEART_RATE, periodo);
    if (leituras.isEmpty) return null;
    return leituras.reduce((a, b) => b.timestamp.isAfter(a.timestamp) ? b : a);
  }

  Future<List<TreinoIntervalo>> lerTreinos(Periodo periodo) async {
    await _garantirConfigurado();
    final pontos = await _health
        .getHealthDataFromTypes(
          types: [HealthDataType.WORKOUT],
          startTime: periodo.inicio,
          endTime: periodo.fim,
        )
        .timeout(_timeoutLeitura, onTimeout: () => []);
    return pontos
        .map((p) => TreinoIntervalo(inicio: p.dateFrom, fim: p.dateTo))
        .toList();
  }

  Future<List<HealthReading>> _lerTipo(HealthDataType tipo, Periodo periodo) async {
    await _garantirConfigurado();
    final pontos = await _health
        .getHealthDataFromTypes(types: [tipo], startTime: periodo.inicio, endTime: periodo.fim)
        .timeout(_timeoutLeitura, onTimeout: () => []);
    return pontos
        .where((p) => p.value is NumericHealthValue)
        .map(
          (p) => HealthReading(
            valor: (p.value as NumericHealthValue).numericValue.toDouble(),
            timestamp: p.dateFrom,
            fim: p.dateTo,
          ),
        )
        .toList();
  }
}

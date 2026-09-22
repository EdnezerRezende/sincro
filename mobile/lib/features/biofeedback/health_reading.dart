/// Uma amostra numérica vinda do HealthKit / Health Connect.
///
/// Leituras de frequência cardíaca e variabilidade são instantâneas (`fim == timestamp`). Amostras
/// de passos são intervalos — o relógio grava "137 passos entre 09:10 e 09:20" —, e é [fim] que
/// permite ao filtro de repouso saber quanto desse intervalo cai dentro da janela que ele avalia.
class HealthReading {
  const HealthReading({required this.valor, required this.timestamp, DateTime? fim})
      : fim = fim ?? timestamp;

  final double valor;
  final DateTime timestamp;

  /// Fim do intervalo da amostra; igual a [timestamp] para leituras instantâneas.
  final DateTime fim;
}

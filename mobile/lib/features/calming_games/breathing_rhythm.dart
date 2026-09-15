import 'dart:math';

/// Guia de respiração puro (sem dependências de Flutter).
///
/// Modela um ciclo de respiração calmante: inspira por [inhaleSeconds] e
/// solta por [exhaleSeconds]. [phase] descreve a "altura" da inspiração ao
/// longo do tempo, de 0 (fim da expiração) a 1 (fim da inspiração), usando
/// uma curva senoidal para que a transição seja suave e sem descontinuidade
/// de derivada nos pontos de virada (início/fim de cada fase).
class BreathingRhythm {
  const BreathingRhythm({this.inhaleSeconds = 4, this.exhaleSeconds = 6})
    : assert(
        inhaleSeconds > 0 && exhaleSeconds > 0,
        'inhaleSeconds e exhaleSeconds devem ser positivos',
      );

  /// Duração da fase de inspiração, em segundos.
  final double inhaleSeconds;

  /// Duração da fase de expiração, em segundos.
  final double exhaleSeconds;

  /// Duração total de um ciclo completo (inspirar + soltar), em segundos.
  double get cycleSeconds => inhaleSeconds + exhaleSeconds;

  /// Retorna o instante equivalente dentro de um único ciclo, em
  /// `[0, cycleSeconds)`. Valores negativos de [t] são tratados como 0, e
  /// valores não finitos (`NaN`, `double.infinity`, `double.negativeInfinity`
  /// — que nunca deveriam aparecer, mas podem vazar de um cálculo de UI com
  /// erro) também são tratados como 0, para nunca propagar `NaN` para a
  /// tela.
  double _localTime(double t) {
    final double safeT = (!t.isFinite || t < 0) ? 0 : t;
    final double cycle = cycleSeconds;
    if (cycle <= 0) return 0;
    double local = safeT % cycle;
    if (local < 0) {
      // Segurança extra: `%` em Dart nunca deveria retornar negativo aqui
      // já que `safeT` é sempre >= 0, mas mantemos por robustez.
      local += cycle;
    }
    return local;
  }

  /// True enquanto o ciclo, no instante [t], está na fase de inspiração.
  bool isInhaling(double t) => _localTime(t) < inhaleSeconds;

  /// Fase da respiração em [t], suave e periódica: sobe de 0 a 1 durante a
  /// inspiração e desce de 1 a 0 durante a expiração, com derivada ~0 nos
  /// pontos de virada (início e fim de cada fase).
  double phase(double t) {
    final double local = _localTime(t);
    if (local <= inhaleSeconds) {
      final double fraction = inhaleSeconds <= 0 ? 1.0 : local / inhaleSeconds;
      return 0.5 - 0.5 * cos(pi * fraction);
    }
    final double fraction = exhaleSeconds <= 0
        ? 1.0
        : (local - inhaleSeconds) / exhaleSeconds;
    return 0.5 + 0.5 * cos(pi * fraction);
  }

  /// Rótulo textual em português para o instante [t]: "Inspire" ou "Solte".
  String label(double t) => isInhaling(t) ? 'Inspire' : 'Solte';
}

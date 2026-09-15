import 'dart:math';

import 'breathing_rhythm.dart';

/// Um "anel de luz" que o avião pode atravessar no jogo Voo Sereno.
///
/// `x` vai de 1.2 (recém-surgido, fora da borda direita) até valores
/// negativos (saiu pela esquerda), quando é removido pelo modelo. `y` é a
/// altura fixa do anel (0..1, mesma escala de [VooSerenoModel.altitude]).
class Ring {
  Ring({required this.x, required this.y, this.passed = false, this.hit = false});

  /// Posição horizontal do anel (1.2 = acabou de aparecer; 0 = centro da
  /// tela; negativo = já saiu pela esquerda).
  double x;

  /// Altura do anel, fixa desde o momento em que foi criado.
  final double y;

  /// True assim que o anel cruza o plano do avião ([VooSerenoModel.planeX]).
  bool passed;

  /// Alias de [passed], para bater com o vocabulário do spec ("cruzar" um
  /// anel). Mesmo valor, não é um estado independente.
  bool get crossed => passed;

  /// True se, no momento em que cruzou o plano, o avião estava alinhado com
  /// o anel (dentro de [VooSerenoModel.ringRadius]).
  bool hit;
}

/// Modelo puro (sem Flutter) do jogo "Voo Sereno".
///
/// Mantém o estado do avião (altitude, velocidade vertical, alvo de toque) e
/// dos anéis de luz que aparecem periodicamente. Determinístico dado o mesmo
/// [seed]: a sequência de alturas dos anéis vem de um `Random(seed)` interno.
///
/// Em produção, a UI deve passar um `seed` específico da sessão (por
/// exemplo `DateTime.now().millisecondsSinceEpoch`) para que a sequência de
/// anéis não repita sempre o mesmo padrão. O padrão `0` é mantido para que
/// os testes sejam determinísticos.
class VooSerenoModel {
  VooSerenoModel({int seed = 0, this.rhythm = const BreathingRhythm()})
    : _random = Random(seed);

  /// Guia de respiração usado para mover o avião quando não há toque.
  final BreathingRhythm rhythm;

  final Random _random;

  /// Posição horizontal (fixa) em que um anel é considerado "atravessado".
  static const double planeX = 0.28;

  /// Distância vertical máxima (em módulo) entre avião e anel para contar
  /// como acerto.
  static const double ringRadius = 0.09;

  static const double _ringSpeed = 0.12; // unidades / segundo, para a esquerda
  static const double _ringSpawnInterval = 8.0; // segundos
  static const double _springOmega = 6.0; // rigidez da mola crítica

  /// Altitude do avião: 0 = topo do céu, 1 = base do céu.
  double altitude = 0.5;

  /// Velocidade vertical atual, em unidades de altitude por segundo.
  double verticalVelocity = 0.0;

  /// Altura alvo definida pelo toque do usuário, ou `null` quando solto (o
  /// avião passa a seguir a onda de respiração).
  double? touchTarget;

  /// Tempo total decorrido desde a criação do modelo, em segundos.
  double elapsed = 0.0;

  /// Anéis atualmente visíveis (ainda não removidos).
  final List<Ring> rings = <Ring>[];

  /// Quantidade de anéis atravessados com sucesso (acertos, isto é, o avião
  /// estava alinhado ao cruzar o anel) até agora — não conta anéis apenas
  /// cruzados sem alinhamento.
  int ringsPassed = 0;

  /// Último anel acertado (permanece definido entre frames para a UI poder
  /// consultar detalhes do acerto mais recente).
  Ring? lastHitRing;

  /// True somente durante o [update] em que um acerto aconteceu — usado pela
  /// UI para disparar haptics sem repetir a cada frame.
  bool hitThisFrame = false;

  double _lastSpawnElapsed = -_ringSpawnInterval;
  double? _previousRingY;

  /// Altura "neutra" do avião quando não há toque, seguindo a respiração:
  /// sobe (altitude menor) durante a inspiração e desce durante a expiração.
  double get breathingAltitude => 0.35 + 0.30 * (1 - rhythm.phase(elapsed));

  /// Inclinação do nariz do avião, proporcional à velocidade vertical para
  /// arrastos moderados, com saturação suave (tangente hiperbólica) para
  /// que velocidades grandes nunca ultrapassem ±12° nem "grudem" no limite
  /// de forma abrupta como um `clamp` linear faria.
  double get pitchRadians {
    const double maxPitch = 12 * pi / 180;
    const double v0 = 0.6; // velocidade de referência da saturação
    return maxPitch * _tanh(verticalVelocity / v0);
  }

  /// Tangente hiperbólica: `dart:math` não a expõe diretamente, então é
  /// implementada aqui a partir de `exp`, já usado pela mola crítica.
  static double _tanh(double x) {
    if (x > 20) return 1.0;
    if (x < -20) return -1.0;
    final double e2x = exp(2 * x);
    return (e2x - 1) / (e2x + 1);
  }

  /// Define a altura alvo (0..1, arredondada para os limites válidos)
  /// conforme o toque do usuário.
  void setTarget(double y) {
    touchTarget = y.clamp(0.0, 1.0);
  }

  /// Solta o toque: o avião volta a seguir a onda de respiração.
  void releaseTouch() {
    touchTarget = null;
  }

  /// Avança a simulação em [dt] segundos (limitado a no máximo 0.1s, para
  /// que uma pausa em segundo plano nunca provoque um salto brusco).
  void update(double dt) {
    final double clampedDt = dt.clamp(0.0, 0.1);
    hitThisFrame = false;
    // `dt <= 0` (incluindo o primeiro callback de um `Ticker`, que sempre
    // chega com `Duration.zero`) deve ser um no-op completo: nada avança,
    // nada nasce. O primeiro anel só aparece no primeiro `update` com
    // `dt > 0`.
    if (clampedDt <= 0) return;

    elapsed += clampedDt;

    final double target = touchTarget ?? breathingAltitude;
    _applySpring(target, clampedDt);

    _spawnRingsIfNeeded();
    _advanceRings(clampedDt);
  }

  void _applySpring(double target, double dt) {
    if (dt <= 0) return;
    final double offset = altitude - target;
    final double temp = (verticalVelocity + _springOmega * offset) * dt;
    final double expTerm = exp(-_springOmega * dt);
    altitude = target + (offset + temp) * expTerm;
    verticalVelocity = (verticalVelocity - _springOmega * temp) * expTerm;
  }

  void _spawnRingsIfNeeded() {
    while (elapsed - _lastSpawnElapsed >= _ringSpawnInterval) {
      _lastSpawnElapsed += _ringSpawnInterval;

      double y;
      if (_previousRingY == null) {
        y = 0.5;
      } else {
        // Passo aleatório seguido de reversão à média (0.5): evita que o
        // passeio aleatório "grude" nas bordas do intervalo (o que
        // aconteceria com um simples `clamp`, já que o clamp empurra
        // repetidamente para o mesmo limite quando o passo continua na
        // mesma direção). O `clamp` final é só uma rede de segurança.
        final double offset = (_random.nextDouble() * 0.5) - 0.25;
        double candidate = _previousRingY! + offset;
        candidate = 0.5 + (candidate - 0.5) * 0.85;
        // Reflexão nas bordas (em vez de clamp): um passo que ultrapassa o
        // limite "quica" de volta para dentro, assim os anéis quase nunca
        // caem exatamente na borda.
        if (candidate < 0.15) candidate = 0.30 - candidate;
        if (candidate > 0.85) candidate = 1.70 - candidate;
        y = candidate.clamp(0.15, 0.85);
      }
      _previousRingY = y;

      rings.add(Ring(x: 1.2, y: y));
    }
  }

  void _advanceRings(double dt) {
    for (final Ring ring in rings) {
      final double previousX = ring.x;
      ring.x -= dt * _ringSpeed;

      if (!ring.passed && previousX > planeX && ring.x <= planeX) {
        ring.passed = true;
        final bool isHit = (altitude - ring.y).abs() <= ringRadius;
        ring.hit = isHit;
        if (isHit) {
          ringsPassed++;
          lastHitRing = ring;
          hitThisFrame = true;
        }
      }
    }

    rings.removeWhere((Ring ring) => ring.x < -0.2);
  }
}

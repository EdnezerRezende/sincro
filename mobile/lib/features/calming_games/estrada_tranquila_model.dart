import 'dart:math';

import 'breathing_rhythm.dart';

/// Tipos de elemento que aparecem ao longo da estrada.
enum RoadItemKind { post, tree, portal }

/// Um elemento visual que percorre a estrada em direção ao carro.
///
/// `z` vai de 1.0 (no horizonte, longe) até 0.0 (na altura do carro) e
/// segue diminuindo até ser removido pelo modelo. `side` indica o lado da
/// pista (-1 esquerda, 1 direita) para postes e árvores; é `null` para
/// portais, que ficam centralizados sobre a pista.
class RoadItem {
  RoadItem({
    required this.kind,
    required this.z,
    this.side,
    this.passed = false,
    this.hit = false,
  });

  final RoadItemKind kind;

  /// Profundidade do item: 1.0 = horizonte, 0.0 = altura do carro, negativo
  /// = já passou do carro (removido logo em seguida).
  double z;

  /// Lado da pista (-1 ou 1) para postes/árvores; `null` para portais.
  final int? side;

  /// True assim que o item cruza o ponto de referência do carro.
  bool passed;

  /// Para portais: true se o carro estava alinhado ao cruzar o portal.
  bool hit;
}

/// Modelo puro (sem Flutter) do jogo "Estrada Tranquila".
///
/// Mantém a posição lateral do carro, a curvatura da pista e os elementos
/// (postes, árvores, portais) que se aproximam ao longo do percurso.
/// Determinístico dado o mesmo [seed].
///
/// Em produção, a UI deve passar um `seed` específico da sessão (por
/// exemplo `DateTime.now().millisecondsSinceEpoch`) para que a curva e os
/// elementos não repitam sempre a mesma sequência. O padrão `0` é mantido
/// para que os testes sejam determinísticos.
class EstradaTranquilaModel {
  EstradaTranquilaModel({int seed = 0, this.rhythm = const BreathingRhythm()})
    : _random = Random(seed);

  /// Guia de respiração usado para o brilho pulsante dos elementos.
  final BreathingRhythm rhythm;

  final Random _random;

  static const double _roadSpeed = 1.0; // unidades de distância / segundo

  /// Velocidade de avanço de `z` (profundidade) por segundo. Um item nasce
  /// em `z = 1.0` e é considerado "na altura do carro" em `z = 0.0`, então
  /// leva `1.0 / itemSpeed` segundos para atravessar a tela — deve ser
  /// >= 6 s (princípio 2 do spec: nada surge rápido, tudo é lento e
  /// previsível). Público e `static const` para permitir teste direto da
  /// cadência.
  static const double itemSpeed = 0.15;

  static const double _springOmega = 6.0; // rigidez da mola crítica lateral
  static const double _curveEaseRate = 0.25; // taxa de suavização exponencial

  static const double _postInterval = 3.5;
  static const double _treeInterval = 5.0;
  static const double _portalInterval = 14.0;
  static const double _curveRedrawInterval = 10.0;

  /// Limiar de `z` em que um portal é considerado atravessado.
  static const double portalCrossZ = 0.05;

  /// Distância lateral máxima (em módulo) do centro para contar como
  /// alinhado ao atravessar um portal.
  static const double portalAlignThreshold = 0.35;

  /// Posição lateral do carro: -1 (extrema esquerda) .. 1 (extrema
  /// direita), 0 = centro.
  double lateral = 0.0;

  /// Velocidade lateral atual, em unidades de posição por segundo.
  double lateralVelocity = 0.0;

  /// Posição lateral alvo definida pelo toque, ou `null` quando solto (o
  /// carro deriva de volta ao centro).
  double? touchTarget;

  /// Curvatura atual da pista, suavizada em direção a [curveTarget].
  double curve = 0.0;

  /// Curvatura alvo, redesenhada periodicamente.
  double curveTarget = 0.0;

  /// Tempo total decorrido desde a criação do modelo, em segundos.
  double elapsed = 0.0;

  /// Distância total percorrida, em "unidades de estrada": como
  /// [_roadSpeed] é constante (1.0 unidade/s), `distance` é numericamente
  /// igual a `elapsed * _roadSpeed` (== `elapsed` no valor atual de
  /// `_roadSpeed`). Usada para cadenciar o surgimento de itens e o desenho
  /// das faixas tracejadas da pista.
  double distance = 0.0;

  /// Elementos visíveis ao longo da estrada.
  final List<RoadItem> items = <RoadItem>[];

  /// Quantidade de portais atravessados com o carro alinhado (acertos).
  int portalsPassed = 0;

  /// True somente durante o [update] em que um portal foi atravessado
  /// alinhado — usado pela UI para disparar haptics sem repetir a cada
  /// frame.
  bool hitThisFrame = false;

  double _lastPostSpawn = -_postInterval;
  double _lastTreeSpawn = -_treeInterval;
  double _lastPortalSpawn = -_portalInterval;
  double _lastCurveRedraw = 0.0;
  int _nextPostSide = 1;

  /// Intensidade do brilho pulsante ligado à respiração (0..1).
  double get breathingGlow => rhythm.phase(elapsed);

  /// Define a posição lateral alvo (clampada a -1..1) conforme o toque do
  /// usuário.
  void setTarget(double x) {
    touchTarget = x.clamp(-1.0, 1.0);
  }

  /// Solta o toque: o carro volta a derivar para o centro.
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
    // nada nasce. O primeiro item só aparece no primeiro `update` com
    // `dt > 0`.
    if (clampedDt <= 0) return;

    elapsed += clampedDt;
    distance += clampedDt * _roadSpeed;

    _updateCurve(clampedDt);
    _applyLateralSpring(clampedDt);
    _spawnItemsIfNeeded();
    _advanceItems(clampedDt);
  }

  void _applyLateralSpring(double dt) {
    if (dt <= 0) return;
    final double target = touchTarget ?? 0.0;
    final double offset = lateral - target;
    final double temp = (lateralVelocity + _springOmega * offset) * dt;
    final double expTerm = exp(-_springOmega * dt);
    lateral = target + (offset + temp) * expTerm;
    lateralVelocity = (lateralVelocity - _springOmega * temp) * expTerm;
  }

  void _updateCurve(double dt) {
    while (distance - _lastCurveRedraw >= _curveRedrawInterval) {
      _lastCurveRedraw += _curveRedrawInterval;
      curveTarget = (_random.nextDouble() * 1.2) - 0.6;
    }
    if (dt <= 0) return;
    final double smoothing = 1 - exp(-_curveEaseRate * dt);
    curve += (curveTarget - curve) * smoothing;
  }

  void _spawnItemsIfNeeded() {
    while (distance - _lastPostSpawn >= _postInterval) {
      _lastPostSpawn += _postInterval;
      items.add(RoadItem(kind: RoadItemKind.post, z: 1.0, side: _nextPostSide));
      _nextPostSide = -_nextPostSide;
    }

    while (distance - _lastTreeSpawn >= _treeInterval) {
      _lastTreeSpawn += _treeInterval;
      final int side = _random.nextBool() ? 1 : -1;
      items.add(RoadItem(kind: RoadItemKind.tree, z: 1.0, side: side));
    }

    while (distance - _lastPortalSpawn >= _portalInterval) {
      _lastPortalSpawn += _portalInterval;
      items.add(RoadItem(kind: RoadItemKind.portal, z: 1.0));
    }
  }

  void _advanceItems(double dt) {
    for (final RoadItem item in items) {
      final double previousZ = item.z;
      item.z -= dt * itemSpeed;

      if (item.kind == RoadItemKind.portal) {
        if (!item.passed && previousZ > portalCrossZ && item.z <= portalCrossZ) {
          item.passed = true;
          final bool aligned = lateral.abs() <= portalAlignThreshold;
          item.hit = aligned;
          if (aligned) {
            portalsPassed++;
            hitThisFrame = true;
          }
        }
      } else if (!item.passed && previousZ > 0 && item.z <= 0) {
        item.passed = true;
      }
    }

    items.removeWhere((RoadItem item) => item.z < -0.1);
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'calming_session_summary.dart';
import 'estrada_tranquila_model.dart';

/// Tela do jogo "Estrada Tranquila": um carro visto de trás percorre uma
/// estrada que se afasta suavemente num ponto de fuga, ao entardecer/noite.
///
/// Sem placar, sem falha: arrastar horizontalmente move o carro; soltar o
/// dedo deixa-o derivar de volta ao centro. Postes, árvores e "portais" de
/// luz passam devagar; o brilho dos postes e dos portais pulsa no ritmo da
/// respiração. Ver `estrada_tranquila_model.dart` para a simulação pura.
class EstradaTranquilaScreen extends StatefulWidget {
  const EstradaTranquilaScreen({super.key, this.seed = 0});

  /// Semente determinística da simulação (útil em testes).
  final int seed;

  @override
  State<EstradaTranquilaScreen> createState() => EstradaTranquilaScreenState();
}

class EstradaTranquilaScreenState extends State<EstradaTranquilaScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final EstradaTranquilaModel _model;
  late final Ticker _ticker;
  Timer? _introHintTimer;
  Duration _lastTick = Duration.zero;

  bool _breathingHintVisible = true;
  bool _hapticsEnabled = true;
  bool _showIntroHint = true;
  bool _showSummary = false;

  /// Exposto apenas para testes de widget (não faz parte da API pública do
  /// jogo): permite inspecionar o estado do modelo puro sem acoplar o teste
  /// à árvore de widgets.
  @visibleForTesting
  EstradaTranquilaModel get debugModel => _model;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _model = EstradaTranquilaModel(seed: widget.seed);
    _ticker = createTicker(_onTick)..start();

    _introHintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showIntroHint = false);
    });
  }

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    if (dt <= 0) return;
    setState(() {
      _model.update(dt);
    });
    if (_model.hitThisFrame && _hapticsEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (_ticker.isActive) _ticker.stop();
        break;
      case AppLifecycleState.resumed:
        if (!_showSummary && !_ticker.isActive) {
          _lastTick = Duration.zero;
          _ticker.start();
        }
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _introHintTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details, double width) {
    _model.setTarget((details.localPosition.dx / width) * 2 - 1);
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    _model.setTarget((details.localPosition.dx / width) * 2 - 1);
  }

  void _onDragEnd(DragEndDetails details) {
    _model.releaseTouch();
  }

  void _onDragCancel() {
    _model.releaseTouch();
  }

  void _onEncerrar() {
    if (_ticker.isActive) _ticker.stop();
    setState(() => _showSummary = true);
  }

  void _resumeSession() {
    setState(() => _showSummary = false);
    _lastTick = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final int minutos = (_model.elapsed / 60).floor();

    if (_showSummary) {
      return Scaffold(
        backgroundColor: scheme.surface,
        body: CalmingSessionSummary(
          elapsed: Duration(milliseconds: (_model.elapsed * 1000).round()),
          gameName: 'Estrada Tranquila',
          onContinue: _resumeSession,
          onExit: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double width = constraints.maxWidth;
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (d) => _onDragStart(d, width),
                    onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
                    onHorizontalDragEnd: _onDragEnd,
                    onHorizontalDragCancel: _onDragCancel,
                    child: Semantics(
                      label: 'Estrada à noite com um carro; arraste para os lados',
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _EstradaPainter(
                          model: _model,
                          scheme: scheme,
                          brightness: Theme.of(context).brightness,
                          reduceMotion: reduceMotion,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _TopPill(minutos: minutos, scheme: scheme),
                ),
                // Controles agrupados no topo, à direita, longe do carro e do
                // portal (a base da tela é o mundo do jogo, não o HUD).
                Positioned(
                  top: 4,
                  right: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RoundIconButton(
                        icon: Icons.air,
                        tooltip: 'Guia de respiração',
                        active: _breathingHintVisible,
                        scheme: scheme,
                        onPressed: () =>
                            setState(() => _breathingHintVisible = !_breathingHintVisible),
                      ),
                      const SizedBox(width: 8),
                      _RoundIconButton(
                        icon: Icons.vibration,
                        tooltip: 'Vibração',
                        active: _hapticsEnabled,
                        scheme: scheme,
                        onPressed: () => setState(() => _hapticsEnabled = !_hapticsEnabled),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Encerrar',
                        iconSize: 28,
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        color: scheme.onSurfaceVariant,
                        onPressed: _onEncerrar,
                      ),
                    ],
                  ),
                ),
                if (_breathingHintVisible)
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: _BreathingLabel(model: _model, scheme: scheme),
                      ),
                    ),
                  ),
                if (_showIntroHint)
                  Positioned(
                    top: 72,
                    left: 24,
                    right: 24,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _showIntroHint ? 1 : 0,
                        duration: const Duration(milliseconds: 800),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'Arraste para os lados. Não há obstáculos, só o caminho.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopPill extends StatelessWidget {
  const _TopPill({required this.minutos, required this.scheme});

  final int minutos;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Estrada Tranquila',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$minutos min',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BreathingLabel extends StatelessWidget {
  const _BreathingLabel({required this.model, required this.scheme});

  final EstradaTranquilaModel model;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final String label = model.rhythm.label(model.elapsed);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 900),
      child: Text(
        '$label…',
        key: ValueKey(label),
        style: TextStyle(
          fontSize: 14,
          color: scheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.scheme,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final ColorScheme scheme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        iconSize: 20,
        color: active ? scheme.primary : scheme.onSurfaceVariant,
        onPressed: onPressed,
      ),
    );
  }
}

/// Pinta o mundo pseudo-3D da estrada: céu, cidade distante, pista com
/// curva, elementos (postes/árvores/portais) e o carro.
class _EstradaPainter extends CustomPainter {
  _EstradaPainter({
    required this.model,
    required this.scheme,
    required this.brightness,
    required this.reduceMotion,
  }) : super();

  final EstradaTranquilaModel model;
  final ColorScheme scheme;
  final Brightness brightness;
  final bool reduceMotion;

  bool get _isDark => brightness == Brightness.dark;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double horizonY = h * 0.42;

    _paintSky(canvas, w, h, horizonY);
    _paintDistantCity(canvas, w, horizonY);
    _paintGround(canvas, w, h, horizonY);
    _paintRoad(canvas, w, h, horizonY);
    _paintItems(canvas, w, h, horizonY);
    _paintHeadlightCone(canvas, w, h, horizonY);
    _paintCar(canvas, w, h);
  }

  // --- Céu -----------------------------------------------------------

  void _paintSky(Canvas canvas, double w, double h, double horizonY) {
    final Rect skyRect = Rect.fromLTWH(0, 0, w, horizonY);
    // Do topo (zênite) até o horizonte: em dusk o azul fica em cima e o
    // pêssego/rosa se concentra junto à linha do horizonte, perto do sol.
    final List<Color> colors = _isDark
        ? const [Color(0xFF0E1626), Color(0xFF1A1F23)]
        : const [Color(0xFFA9C6E8), Color(0xFFCBAED6), Color(0xFFF4B893)];
    final List<double> stops = _isDark ? const [0.0, 1.0] : const [0.0, 0.6, 1.0];
    final Paint skyPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, horizonY),
        colors,
        stops,
      );
    canvas.drawRect(skyRect, skyPaint);

    if (_isDark) {
      final math.Random starRandom = math.Random(7);
      final double twinkle = reduceMotion
          ? 1.0
          : 0.7 + 0.3 * math.sin(model.elapsed * 0.6);
      final Paint starPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.55 * twinkle);
      for (int i = 0; i < 28; i++) {
        final double sx = starRandom.nextDouble() * w;
        final double sy = starRandom.nextDouble() * horizonY * 0.8;
        final double r = 0.6 + starRandom.nextDouble() * 1.0;
        canvas.drawCircle(Offset(sx, sy), r, starPaint);
      }
    }
  }

  void _paintDistantCity(Canvas canvas, double w, double horizonY) {
    final math.Random cityRandom = math.Random(42);
    final Paint dotPaint = Paint()
      ..color = (_isDark ? const Color(0xFFFFD9A0) : const Color(0xFFFFF3D6))
          .withValues(alpha: _isDark ? 0.75 : 0.5);
    final double stripY = horizonY - 3;
    for (int i = 0; i < 40; i++) {
      final double x = cityRandom.nextDouble() * w;
      final double y = stripY - cityRandom.nextDouble() * 10;
      final double r = 0.8 + cityRandom.nextDouble() * 1.4;
      canvas.drawCircle(Offset(x, y), r, dotPaint);
    }
  }

  // --- Solo / pista ----------------------------------------------------

  void _paintGround(Canvas canvas, double w, double h, double horizonY) {
    final Rect groundRect = Rect.fromLTWH(0, horizonY, w, h - horizonY);
    final List<Color> colors = _isDark
        ? const [Color(0xFF1A1F23), Color(0xFF11151A)]
        : const [Color(0xFF869C88), Color(0xFF51695A)];
    final Paint groundPaint = Paint()
      ..shader = ui.Gradient.linear(Offset(0, horizonY), Offset(0, h), colors);
    canvas.drawRect(groundRect, groundPaint);
  }

  /// Metade da largura da pista, em pixels, junto ao carro (`z` = 0). Usada
  /// tanto pela projeção da pista quanto para posicionar o carro e o cone
  /// dos faróis na mesma escala.
  double _roadHalfWidthAt(double t, double w) => w * 0.006 + (w * 0.404) * t * t;

  /// Projeta um ponto lógico (lado -1..1 relativo à largura da pista naquele
  /// z, e profundidade z 1..0) para coordenadas de tela, aplicando a
  /// perspectiva e a curva. A largura da pista segue a mesma aceleração
  /// quadrática que a projeção vertical, para que as bordas convirjam em
  /// linhas retas até o ponto de fuga (em vez de "abrirem" cedo demais).
  Offset _project(double side, double z, double w, double h, double horizonY) {
    final double t = (1 - z);
    final double screenY = horizonY + (h - horizonY) * t * t;
    final double roadHalfWidth = _roadHalfWidthAt(t, w);
    final double curveOffset = model.curve * w * 0.32 * (1 - t) * (1 - t);
    final double centerX = w / 2 + curveOffset;
    return Offset(centerX + side * roadHalfWidth, screenY);
  }

  void _paintRoad(Canvas canvas, double w, double h, double horizonY) {
    const int segments = 24;
    final Path road = Path();
    final List<Offset> left = [];
    final List<Offset> right = [];
    for (int i = 0; i <= segments; i++) {
      final double z = 1 - i / segments;
      left.add(_project(-1, z, w, h, horizonY));
      right.add(_project(1, z, w, h, horizonY));
    }
    road.moveTo(left.first.dx, left.first.dy);
    for (final Offset p in left.skip(1)) {
      road.lineTo(p.dx, p.dy);
    }
    for (final Offset p in right.reversed) {
      road.lineTo(p.dx, p.dy);
    }
    road.close();

    final Color roadFar = _isDark ? const Color(0xFF23282E) : const Color(0xFF4A4A52);
    final Color roadNear = _isDark ? const Color(0xFF2E343B) : const Color(0xFF5C5C66);
    final Paint roadPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(w / 2, horizonY),
        Offset(w / 2, h),
        [roadFar, roadNear],
      );
    canvas.drawPath(road, roadPaint);

    // Acostamento suave: uma linha clara e fina em cada borda, para dar
    // definição à pista sem criar contraste alto (apenas uma sugestão de
    // profundidade).
    final Paint shoulderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = (_isDark ? const Color(0xFFB8C4CC) : Colors.white).withValues(alpha: 0.22);
    final Path leftEdge = Path()..moveTo(left.first.dx, left.first.dy);
    for (final Offset p in left.skip(1)) {
      leftEdge.lineTo(p.dx, p.dy);
    }
    final Path rightEdge = Path()..moveTo(right.first.dx, right.first.dy);
    for (final Offset p in right.skip(1)) {
      rightEdge.lineTo(p.dx, p.dy);
    }
    shoulderPaint.strokeWidth = 1.2;
    canvas.drawPath(leftEdge, shoulderPaint);
    canvas.drawPath(rightEdge, shoulderPaint);

    // Linha central tracejada, fase seguindo a distância percorrida.
    final Paint dashPaint = Paint()
      ..color = (_isDark ? Colors.white : Colors.white).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke;
    const double dashLength = 0.045; // em unidades de z
    final double phase = (model.distance * 0.35) % dashLength;
    double z = 1 - phase;
    while (z > 0) {
      final double zEnd = math.max(z - dashLength * 0.55, 0);
      final Offset p1 = _project(0, z, w, h, horizonY);
      final Offset p2 = _project(0, zEnd, w, h, horizonY);
      final double t = 1 - z;
      dashPaint.strokeWidth = 1 + 3 * t;
      canvas.drawLine(p1, p2, dashPaint);
      z -= dashLength;
    }
  }

  // --- Elementos (postes, árvores, portais) ---------------------------

  void _paintItems(Canvas canvas, double w, double h, double horizonY) {
    final List<RoadItem> sorted = List.of(model.items)
      ..sort((a, b) => b.z.compareTo(a.z));
    for (final RoadItem item in sorted) {
      final double z = item.z.clamp(0.0, 1.0);
      switch (item.kind) {
        case RoadItemKind.post:
          _paintPost(canvas, w, h, horizonY, item, z);
        case RoadItemKind.tree:
          _paintTree(canvas, w, h, horizonY, item, z);
        case RoadItemKind.portal:
          _paintPortal(canvas, w, h, horizonY, item, z);
      }
    }
  }

  void _paintPost(Canvas canvas, double w, double h, double horizonY, RoadItem item, double z) {
    final int side = item.side ?? 1;
    final double t = 1 - z;
    final double scale = 0.15 + t * 1.4;
    final Offset base = _project(side * 1.12, z, w, h, horizonY);
    final double postHeight = 26 * scale;
    final double postWidth = 1.6 * scale;

    final Color poleColor = _isDark ? const Color(0xFF3A3F45) : const Color(0xFF2E2E33);
    final Paint polePaint = Paint()
      ..color = poleColor.withValues(alpha: 0.85);
    canvas.drawRect(
      Rect.fromLTWH(base.dx - postWidth / 2, base.dy - postHeight, postWidth, postHeight),
      polePaint,
    );

    final double pulse = reduceMotion ? 0.75 : 0.55 + 0.45 * model.breathingGlow;
    final double haloRadius = (7 + t * 20) * (0.7 + 0.3 * pulse);
    final Offset lampCenter = Offset(base.dx, base.dy - postHeight);
    final Color warm = _isDark ? const Color(0xFFFFD9A0) : const Color(0xFFFFE9C2);
    final Paint haloPaint = Paint()
      ..shader = ui.Gradient.radial(
        lampCenter,
        haloRadius,
        [
          warm.withValues(alpha: 0.55 * pulse),
          warm.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(lampCenter, haloRadius, haloPaint);
    canvas.drawCircle(
      lampCenter,
      2.2 * scale,
      Paint()..color = warm.withValues(alpha: 0.9),
    );
  }

  void _paintTree(Canvas canvas, double w, double h, double horizonY, RoadItem item, double z) {
    final int side = item.side ?? 1;
    final double t = 1 - z;
    final double scale = 0.15 + t * 1.6;
    final Offset base = _project(side * 1.28, z, w, h, horizonY);
    final double trunkHeight = 10 * scale;
    final double canopyRadius = 12 * scale;

    final Color trunkColor = _isDark ? const Color(0xFF2A2F26) : const Color(0xFF3C3A2E);
    canvas.drawRect(
      Rect.fromLTWH(base.dx - 1.2 * scale, base.dy - trunkHeight, 2.4 * scale, trunkHeight),
      Paint()..color = trunkColor.withValues(alpha: 0.8),
    );

    final Color canopyColor = _isDark ? const Color(0xFF223328) : const Color(0xFF2F4A38);
    final Offset canopyCenter = Offset(base.dx, base.dy - trunkHeight - canopyRadius * 0.6);
    canvas.drawCircle(
      canopyCenter,
      canopyRadius,
      Paint()
        ..color = canopyColor.withValues(alpha: 0.75)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
  }

  void _paintPortal(Canvas canvas, double w, double h, double horizonY, RoadItem item, double z) {
    final double t = 1 - z;
    final Offset base = _project(0, z, w, h, horizonY);
    final double archWidth = w * (0.14 + t * 0.5);
    final double archHeight = archWidth * 0.9;

    double brightness = 0.35 + 0.2 * model.breathingGlow;
    if (item.passed) {
      // Recém-atravessado: breve realce que esmaece.
      final double fade = (1 - (0.05 - z).abs() / 0.35).clamp(0.0, 1.0);
      if (item.hit) brightness += 0.5 * fade;
    }
    brightness = brightness.clamp(0.0, 1.0);

    final Color arcColor = _isDark ? const Color(0xFF8FE3E8) : const Color(0xFFBFE3FF);
    final Rect archRect = Rect.fromCenter(
      center: Offset(base.dx, base.dy - archHeight / 2),
      width: archWidth,
      height: archHeight,
    );

    final Paint glowPaint = Paint()
      ..color = arcColor.withValues(alpha: 0.18 * brightness)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 10 * brightness);
    canvas.drawArc(archRect, math.pi, math.pi, false, glowPaint);

    final Paint arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 + 3 * t
      ..strokeCap = StrokeCap.round
      ..color = arcColor.withValues(alpha: 0.35 + 0.5 * brightness);
    canvas.drawArc(archRect, math.pi, math.pi, false, arcPaint);
  }

  // --- Carro / farol ----------------------------------------------------

  void _paintHeadlightCone(Canvas canvas, double w, double h, double horizonY) {
    final double carX = w / 2 + model.lateral * _roadHalfWidthAt(1, w) * 0.6;
    final double carTop = h - h * 0.14;
    final Path cone = Path()
      ..moveTo(carX - w * 0.05, carTop)
      ..lineTo(carX - w * 0.22, horizonY + (h - horizonY) * 0.28)
      ..lineTo(carX + w * 0.22, horizonY + (h - horizonY) * 0.28)
      ..lineTo(carX + w * 0.05, carTop)
      ..close();
    final Color beam = _isDark ? const Color(0xFFFFF3D2) : const Color(0xFFFFFAE8);
    final Paint conePaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(carX, carTop),
        Offset(carX, horizonY + (h - horizonY) * 0.28),
        [beam.withValues(alpha: _isDark ? 0.22 : 0.12), beam.withValues(alpha: 0.0)],
      );
    canvas.drawPath(cone, conePaint);
  }

  void _paintCar(Canvas canvas, double w, double h) {
    final double carX = w / 2 + model.lateral * _roadHalfWidthAt(1, w) * 0.6;
    final double carY = h - h * 0.10;
    final double carWidth = w * 0.24;
    final double carHeight = carWidth * 0.62;

    final double tilt = (model.lateralVelocity * 0.35).clamp(-6.0, 6.0) * math.pi / 180;

    canvas.save();
    canvas.translate(carX, carY);
    canvas.rotate(tilt);

    final RRect body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: carWidth, height: carHeight),
      Radius.circular(carWidth * 0.18),
    );
    final Color bodyColor = _isDark ? const Color(0xFF3C4650) : const Color(0xFF465A66);
    canvas.drawRRect(
      body,
      Paint()..color = bodyColor.withValues(alpha: 0.92),
    );

    // Vidro traseiro
    final RRect glass = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, -carHeight * 0.22),
        width: carWidth * 0.6,
        height: carHeight * 0.42,
      ),
      Radius.circular(carWidth * 0.1),
    );
    canvas.drawRRect(
      glass,
      Paint()..color = (_isDark ? Colors.black : Colors.black).withValues(alpha: 0.22),
    );

    // Luzes traseiras: âmbar/rosa suave, nunca vermelho.
    final double lightRadius = carWidth * 0.06;
    final Offset leftLight = Offset(-carWidth * 0.34, carHeight * 0.28);
    final Offset rightLight = Offset(carWidth * 0.34, carHeight * 0.28);
    final Color tailColor = _isDark ? const Color(0xFFFFB088) : const Color(0xFFFFAE94);
    for (final Offset pos in [leftLight, rightLight]) {
      canvas.drawCircle(
        pos,
        lightRadius * 2.2,
        Paint()
          ..color = tailColor.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(pos, lightRadius, Paint()..color = tailColor.withValues(alpha: 0.85));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EstradaPainter oldDelegate) {
    return true;
  }
}

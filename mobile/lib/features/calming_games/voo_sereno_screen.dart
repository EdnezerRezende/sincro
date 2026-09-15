import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'calming_session_summary.dart';
import 'voo_sereno_model.dart';

/// Tela do jogo de regulação sensorial "Voo Sereno": um avião de papel voa
/// devagar por um céu ao entardecer, guiado pelo dedo (ou pela respiração,
/// quando solto). Sem placar, sem falha — ver `SPEC.md` de
/// `lib/features/calming_games/` para os princípios completos.
class VooSerenoScreen extends StatefulWidget {
  const VooSerenoScreen({super.key, this.seed = 0});

  /// Semente do modelo (determinismo em testes).
  final int seed;

  @override
  State<VooSerenoScreen> createState() => VooSerenoScreenState();
}

class VooSerenoScreenState extends State<VooSerenoScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final VooSerenoModel _model = VooSerenoModel(seed: widget.seed);
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// Notifica a cada frame simulado, para repintar o `CustomPaint` e
  /// atualizar o overlay textual sem reconstruir a árvore de widgets toda.
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  bool _showSummary = false;
  bool _breathingHintOn = true;
  bool _hapticsOn = true;

  /// Expõe o modelo para os testes de widget (não usar em produção).
  @visibleForTesting
  VooSerenoModel get debugModel => _model;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    if (dt <= 0) return;

    _model.update(dt);
    if (_model.hitThisFrame && _hapticsOn) {
      HapticFeedback.lightImpact();
    }
    _tick.value++;
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

  void _endSession() {
    if (_ticker.isActive) _ticker.stop();
    setState(() => _showSummary = true);
  }

  void _setTargetFromLocalY(double localY, double height) {
    if (height <= 0) return;
    _model.setTarget(localY / height);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: _showSummary
          ? CalmingSessionSummary(
              elapsed: Duration(seconds: _model.elapsed.round()),
              gameName: 'Voo Sereno',
              onClose: () => Navigator.of(context).maybePop(),
            )
          : SafeArea(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        final double height = constraints.maxHeight;
                        return Semantics(
                          label: 'Céu com avião de papel; arraste para subir ou descer',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanDown: (DragDownDetails d) =>
                                _setTargetFromLocalY(d.localPosition.dy, height),
                            onVerticalDragStart: (DragStartDetails d) =>
                                _setTargetFromLocalY(d.localPosition.dy, height),
                            onVerticalDragUpdate: (DragUpdateDetails d) =>
                                _setTargetFromLocalY(d.localPosition.dy, height),
                            onVerticalDragEnd: (_) => _model.releaseTouch(),
                            onVerticalDragCancel: () => _model.releaseTouch(),
                            child: AnimatedBuilder(
                              animation: _tick,
                              builder: (BuildContext context, Widget? _) {
                                return CustomPaint(
                                  size: Size.infinite,
                                  painter: _VooSerenoPainter(
                                    model: _model,
                                    colorScheme: scheme,
                                    reduceMotion: reduceMotion,
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Dica de primeiro uso, só nos primeiros 5s, não intercepta toques.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _tick,
                        builder: (BuildContext context, Widget? _) {
                          final double t = _model.elapsed;
                          final double opacity = t >= 5
                              ? 0.0
                              : (t < 3.5 ? 1.0 : (5 - t) / 1.5).clamp(0.0, 1.0);
                          if (opacity <= 0) return const SizedBox.shrink();
                          return Align(
                            alignment: const Alignment(0, -0.35),
                            child: Opacity(
                              opacity: opacity,
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 40),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: scheme.surface.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  'Arraste para cima ou para baixo. Sem pressa, sem placar.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: scheme.onSurface,
                                      ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Pill superior esquerda: nome do jogo + minutos.
                  Positioned(
                    top: 12,
                    left: 12,
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _tick,
                        builder: (BuildContext context, Widget? _) {
                          final int minutes = (_model.elapsed / 60).floor();
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Voo Sereno · $minutes min',
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Ações superior direita: guia de respiração, haptics, encerrar.
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Guia de respiração',
                          icon: Icon(
                            Icons.air,
                            color: _breathingHintOn ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                          onPressed: () => setState(() => _breathingHintOn = !_breathingHintOn),
                        ),
                        IconButton(
                          tooltip: 'Vibração',
                          icon: Icon(
                            _hapticsOn ? Icons.vibration : Icons.mobile_off,
                            color: _hapticsOn ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                          onPressed: () => setState(() => _hapticsOn = !_hapticsOn),
                        ),
                        IconButton(
                          tooltip: 'Encerrar',
                          icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                          onPressed: _endSession,
                        ),
                      ],
                    ),
                  ),

                  // Dica de respiração, parte inferior central.
                  if (_breathingHintOn)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 24,
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _tick,
                          builder: (BuildContext context, Widget? _) {
                            final String label = _model.rhythm.label(_model.elapsed);
                            return Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 700),
                                child: Text(
                                  '$label…',
                                  key: ValueKey<String>(label),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: scheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Pinta o céu, o sol/lua com halo, as nuvens em parallax, pássaros
/// distantes, os anéis de luz e o avião de papel do jogo Voo Sereno.
class _VooSerenoPainter extends CustomPainter {
  _VooSerenoPainter({
    required this.model,
    required this.colorScheme,
    required this.reduceMotion,
  });

  final VooSerenoModel model;
  final ColorScheme colorScheme;
  final bool reduceMotion;

  bool get _isDark => colorScheme.brightness == Brightness.dark;

  // Réplica do valor de `VooSerenoModel._ringSpeed` (unidades/s), usada só
  // para estimar visualmente há quanto tempo um anel foi atravessado, sem
  // alterar o arquivo do modelo.
  static const double _ringSpeedReplica = 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    _paintCelestialBody(canvas, size);
    _paintClouds(canvas, size);
    _paintBirds(canvas, size);
    for (final Ring ring in model.rings) {
      _paintRing(canvas, size, ring);
    }
    _paintPlane(canvas, size);
  }

  void _paintSky(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    // Três paradas para uma transição de entardecer mais rica: azul pálido
    // no topo, um meio-tom lilás e um horizonte quente (pêssego/grafite).
    final List<Color> colors = _isDark
        ? const <Color>[Color(0xFF0A1220), Color(0xFF161E2E), Color(0xFF1A1F23)]
        : const <Color>[Color(0xFFCDE6F7), Color(0xFFE6D3EA), Color(0xFFF6D9C4)];
    final Paint paint = Paint()
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        colors,
        const <double>[0.0, 0.55, 1.0],
      );
    canvas.drawRect(rect, paint);
  }

  void _paintCelestialBody(Canvas canvas, Size size) {
    final Offset center = _isDark
        ? Offset(size.width * 0.76, size.height * 0.22)
        : Offset(size.width * 0.80, size.height * 0.66);

    final double breathPulse = reduceMotion ? 0.0 : (model.rhythm.phase(model.elapsed) - 0.5) * 2;
    final double haloRadius = size.width * (0.34 + 0.02 * breathPulse);
    final double discRadius = size.width * 0.052;

    final Color glowColor = _isDark ? const Color(0xFFBFE0F0) : const Color(0xFFFFD9A0);
    final Color discColor = _isDark ? const Color(0xFFEAF3F8) : const Color(0xFFFFF6E4);

    // Halo externo, bem suave e largo, para dar profundidade atmosférica.
    final Paint outerHalo = Paint()
      ..shader = ui.Gradient.radial(
        center,
        haloRadius * 1.9,
        <Color>[glowColor.withValues(alpha: _isDark ? 0.10 : 0.14), glowColor.withValues(alpha: 0.0)],
      );
    canvas.drawCircle(center, haloRadius * 1.9, outerHalo);

    final Paint halo = Paint()
      ..shader = ui.Gradient.radial(
        center,
        haloRadius,
        <Color>[glowColor.withValues(alpha: _isDark ? 0.26 : 0.34), glowColor.withValues(alpha: 0.0)],
      );
    canvas.drawCircle(center, haloRadius, halo);

    final Paint disc = Paint()
      ..color = discColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    canvas.drawCircle(center, discRadius, disc);
  }

  /// Fração horizontal (0..1, com folga de 0.2 de cada lado) de um elemento
  /// de parallax que se move para a esquerda com velocidade [speed]
  /// (unidades/s) e fase [phase] (0..1), calculada a partir de
  /// `model.elapsed` — sem estado adicional, determinística.
  double _parallaxFraction(double speed, double phase) {
    final double raw = -(model.elapsed * speed) - phase;
    final double wrapped = raw - (raw.floorToDouble());
    return wrapped; // sempre em [0,1)
  }

  void _paintClouds(Canvas canvas, Size size) {
    final Color cloudColor = _isDark ? const Color(0xFFB9C7D6) : const Color(0xFFFFFFFF);

    final List<_CloudLayer> layers = reduceMotion
        ? const <_CloudLayer>[_CloudLayer(speed: 0.05, y: 0.30, scale: 1.0, opacity: 0.5, count: 2)]
        : const <_CloudLayer>[
            _CloudLayer(speed: 0.02, y: 0.18, scale: 0.8, opacity: 0.28, count: 2),
            _CloudLayer(speed: 0.05, y: 0.32, scale: 1.05, opacity: 0.42, count: 2),
            _CloudLayer(speed: 0.09, y: 0.48, scale: 1.35, opacity: 0.60, count: 2),
          ];

    for (final _CloudLayer layer in layers) {
      for (int i = 0; i < layer.count; i++) {
        final double phase = i / layer.count;
        final double f = _parallaxFraction(layer.speed, phase);
        final double x = size.width * (1.4 * f - 0.2);
        final double y = size.height * layer.y;
        _drawCloud(
          canvas,
          Offset(x, y),
          size.width * 0.14 * layer.scale,
          cloudColor.withValues(alpha: layer.opacity),
        );
      }
    }
  }

  void _drawCloud(Canvas canvas, Offset center, double radius, Color color) {
    // Nuvem "fofa" feita de lóbulos sobrepostos com raios/opacidades
    // ligeiramente diferentes e uma leve borrada (`MaskFilter.blur`), para
    // evitar o efeito de "flor de círculos" e parecer mais macia/pintada.
    final Paint paint = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.16);
    final List<(Offset, double, double)> lobes = <(Offset, double, double)>[
      (Offset(-radius * 0.72, radius * 0.14), radius * 0.58, 0.75),
      (Offset(-radius * 0.18, -radius * 0.22), radius * 0.62, 0.95),
      (Offset(radius * 0.30, -radius * 0.02), radius * 0.72, 1.0),
      (Offset(radius * 0.78, radius * 0.12), radius * 0.50, 0.70),
      (Offset(radius * 0.05, radius * 0.20), radius * 0.66, 0.85),
    ];
    for (final (Offset offset, double lobeRadius, double lobeAlpha) in lobes) {
      paint.color = color.withValues(alpha: (color.a) * lobeAlpha);
      canvas.drawCircle(center + offset, lobeRadius, paint);
    }
  }

  void _paintBirds(Canvas canvas, Size size) {
    if (reduceMotion) return;
    final Paint paint = Paint()
      ..color = colorScheme.onSurfaceVariant.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    const int birdCount = 3;
    for (int i = 0; i < birdCount; i++) {
      final double phase = i / birdCount;
      final double f = _parallaxFraction(0.035 + i * 0.01, phase);
      final double x = size.width * (1.4 * f - 0.2);
      final double y = size.height * (0.12 + 0.05 * i);
      final double w = size.width * 0.02;
      final Path path = Path()
        ..moveTo(x - w, y)
        ..quadraticBezierTo(x, y + w * 0.7, x, y)
        ..quadraticBezierTo(x, y + w * 0.7, x + w, y);
      canvas.drawPath(path, paint);
    }
  }

  void _paintRing(Canvas canvas, Size size, Ring ring) {
    final Offset center = Offset(size.width * ring.x, size.height * ring.y);
    final double radius = size.height * VooSerenoModel.ringRadius;

    double alpha = 0.55;
    double glowBoost = 0.0;
    if (ring.hit) {
      final double timeSincePass =
          ((VooSerenoModel.planeX - ring.x) / _ringSpeedReplica).clamp(0.0, 10.0);
      final double fade = timeSincePass.clamp(0.0, 1.0);
      alpha = 1.0 - fade;
      glowBoost = 1.0 - fade;
      if (alpha <= 0.01) return;
    } else if (ring.x > 1.15 || ring.x < -0.15) {
      return;
    }

    // Em tema claro, o `primary` puro é saturado demais para um "anel de
    // luz" suave sobre um céu pastel — clareamos um pouco. No tema escuro o
    // ciano vibrante já contrasta bem com o céu grafite/azul-marinho.
    final Color ringColor = _isDark
        ? colorScheme.primary
        : Color.lerp(colorScheme.primary, Colors.white, 0.35)!;

    final Paint glow = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius * (1.6 + glowBoost * 0.8),
        <Color>[ringColor.withValues(alpha: 0.28 * alpha + glowBoost * 0.35), ringColor.withValues(alpha: 0.0)],
      );
    canvas.drawCircle(center, radius * (1.6 + glowBoost * 0.8), glow);

    final Paint stroke = Paint()
      ..color = ringColor.withValues(alpha: (0.55 + glowBoost * 0.45) * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 + glowBoost * 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
    canvas.drawCircle(center, radius, stroke);
  }

  void _paintPlane(Canvas canvas, Size size) {
    final Offset center = Offset(size.width * VooSerenoModel.planeX, size.height * model.altitude);
    final double scale = size.width * 0.155;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(model.pitchRadians);

    // Rastro (contrail): 3 pontos esmaecendo atrás do avião — discreto, mas
    // visível o suficiente para sugerir movimento contínuo.
    final Paint trailPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 1; i <= 3; i++) {
      final double dx = -scale * (1.05 + i * 0.42);
      final double r = scale * (0.075 - i * 0.014);
      trailPaint.color = colorScheme.onSurfaceVariant.withValues(alpha: 0.30 / i);
      canvas.drawCircle(Offset(dx, 0), r, trailPaint);
    }

    final Color paperColor = _isDark ? const Color(0xFFF3F9FC) : const Color(0xFFFFFFFF);
    final Color paperShadow = _isDark ? const Color(0xFFA9C0CE) : const Color(0xFFD9CFC0);
    final Paint outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = colorScheme.onSurface.withValues(alpha: _isDark ? 0.18 : 0.14);

    // Corpo (fuselagem) e duas "asas" dobradas, como um avião de papel
    // simples visto de lado, apontando para a direita.
    final Path body = Path()
      ..moveTo(scale, 0)
      ..lineTo(-scale * 0.85, -scale * 0.34)
      ..lineTo(-scale * 0.30, 0)
      ..close();
    final Path wingTop = Path()
      ..moveTo(scale * 0.45, -scale * 0.02)
      ..lineTo(-scale * 0.75, -scale * 0.62)
      ..lineTo(-scale * 0.45, -scale * 0.06)
      ..close();
    final Path tailFin = Path()
      ..moveTo(-scale * 0.35, 0)
      ..lineTo(-scale * 0.9, scale * 0.32)
      ..lineTo(-scale * 0.55, scale * 0.02)
      ..close();

    canvas.drawPath(wingTop, Paint()..color = paperShadow);
    canvas.drawPath(wingTop, outline);
    canvas.drawPath(tailFin, Paint()..color = paperShadow.withValues(alpha: 0.85));
    canvas.drawPath(tailFin, outline);
    canvas.drawPath(body, Paint()..color = paperColor);
    canvas.drawPath(body, outline);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VooSerenoPainter oldDelegate) => true;
}

class _CloudLayer {
  const _CloudLayer({
    required this.speed,
    required this.y,
    required this.scale,
    required this.opacity,
    required this.count,
  });

  final double speed;
  final double y;
  final double scale;
  final double opacity;
  final int count;
}

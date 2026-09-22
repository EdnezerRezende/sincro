import 'package:flutter/material.dart';

import 'serie_dia.dart';

/// Faixa pessoal de repouso (μ±1,5σ) calculada a partir do histórico do usuário.
typedef FaixaRepouso = ({double minimo, double maximo});

/// Gráfico intraday de frequência cardíaca — Variante A ("linha contínua").
///
/// Desenha a série de hoje como uma linha contínua de médias de blocos de 5 minutos, com
/// trechos de atividade (`emRepouso == false`) num tom neutro e trechos de repouso em `primary`
/// com uma área sombreada por baixo. Marca só pico e vale com rótulo direto; o resto do eixo Y
/// é lido pelas gridlines. Não é um cartão — quem chama envolve com o chrome (`TonalPanel`,
/// `Card` etc.).
class BiofeedbackDailyChart extends StatefulWidget {
  const BiofeedbackDailyChart({
    super.key,
    required this.serie,
    required this.agora,
    this.faixaRepouso,
    this.fcRepouso,
    this.altura = 220,
  });

  /// Série agregada do dia mostrado no gráfico.
  final SerieDia serie;

  /// Instante atual: o domínio do eixo X é sempre 00:00 → 24:00 do dia de [serie], mas os dados
  /// terminam aqui (o resto do dia fica sem linha).
  final DateTime agora;

  /// Faixa pessoal de repouso (μ±1,5σ). `null` enquanto o app ainda não tem histórico suficiente.
  final FaixaRepouso? faixaRepouso;

  /// Frequência cardíaca de repouso nativa do relógio. `null` quando o relógio ainda não informou.
  final double? fcRepouso;

  final double altura;

  @override
  State<BiofeedbackDailyChart> createState() => _BiofeedbackDailyChartState();
}

String _formatoHora(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Chave estável do `CustomPaint` interno, para testes localizarem o canvas do gráfico entre
/// outros `CustomPaint` incidentais da árvore (gestos, Material etc.).
const biofeedbackDailyChartCanvasKey = ValueKey('biofeedbackDailyChartACanvas');

class _BiofeedbackDailyChartState extends State<BiofeedbackDailyChart> {
  /// Índice do bloco selecionado por toque/arrasto (`-1` = nenhuma seleção).
  int _selecionado = -1;

  DateTime get _inicioDoDia => DateTime(widget.serie.dia.year, widget.serie.dia.month, widget.serie.dia.day);

  void _selecionarNaPosicao(Offset posicaoLocal, Size tamanho, _ChartGeometry geo) {
    final pontos = widget.serie.pontos;
    if (pontos.isEmpty) return;
    // Converte x local em fração do dia (0..1) e acha o bloco mais próximo por horário.
    final fracaoDia = ((posicaoLocal.dx - geo.plotLeft) / geo.plotWidth).clamp(0.0, 1.0);
    final minutosDoDia = fracaoDia * 24 * 60;
    var melhorIndice = 0;
    var melhorDistancia = double.infinity;
    for (var i = 0; i < pontos.length; i++) {
      final minutosPonto = pontos[i].inicio.difference(_inicioDoDia).inMinutes.toDouble() +
          SerieDia.duracaoBloco.inMinutes / 2;
      final distancia = (minutosPonto - minutosDoDia).abs();
      if (distancia < melhorDistancia) {
        melhorDistancia = distancia;
        melhorIndice = i;
      }
    }
    setState(() => _selecionado = melhorIndice);
  }

  String _semanticsLabel() {
    final serie = widget.serie;
    if (serie.vazia) return 'Frequência cardíaca de hoje: sem leituras hoje ainda.';
    final pico = serie.pico!;
    final vale = serie.vale!;
    final ultimo = serie.ultimo!;
    return 'Frequência cardíaca de hoje: mínima ${vale.minimo.round()} bpm às '
        '${_formatoHora(vale.inicio)}, máxima ${pico.maximo.round()} bpm às '
        '${_formatoHora(pico.inicio)}, última ${ultimo.media.round()} bpm às '
        '${_formatoHora(ultimo.inicio)}.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return Semantics(
      label: _semanticsLabel(),
      child: SizedBox(
        height: widget.altura,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tamanho = Size(constraints.maxWidth, widget.altura);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final geo = _ChartGeometry.calcular(tamanho, widget.serie, widget.faixaRepouso, widget.fcRepouso);
                if (details.localPosition.dx < geo.plotLeft || details.localPosition.dx > geo.plotLeft + geo.plotWidth) {
                  setState(() => _selecionado = -1);
                  return;
                }
                _selecionarNaPosicao(details.localPosition, tamanho, geo);
              },
              onHorizontalDragUpdate: (details) {
                final geo = _ChartGeometry.calcular(tamanho, widget.serie, widget.faixaRepouso, widget.fcRepouso);
                _selecionarNaPosicao(details.localPosition, tamanho, geo);
              },
              child: CustomPaint(
                key: biofeedbackDailyChartCanvasKey,
                size: tamanho,
                painter: _DailyChartPainter(
                  serie: widget.serie,
                  agora: widget.agora,
                  faixaRepouso: widget.faixaRepouso,
                  fcRepouso: widget.fcRepouso,
                  selecionado: _selecionado,
                  theme: theme,
                  textScaler: textScaler,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Geometria derivada (domínios, escala, retângulo do gráfico) — calculada uma vez e
/// compartilhada entre o gesto de seleção e o painter, para os dois lerem o mesmo mapeamento.
class _ChartGeometry {
  _ChartGeometry({
    required this.plotLeft,
    required this.plotTop,
    required this.plotWidth,
    required this.plotHeight,
    required this.yMin,
    required this.yMax,
  });

  final double plotLeft;
  final double plotTop;
  final double plotWidth;
  final double plotHeight;
  final double yMin;
  final double yMax;

  static const _padEsquerda = 40.0;
  static const _padDireita = 12.0;
  static const _padTopo = 12.0;
  static const _padBase = 24.0;

  static _ChartGeometry calcular(
    Size tamanho,
    SerieDia serie,
    FaixaRepouso? faixaRepouso,
    double? fcRepouso,
  ) {
    final plotLeft = _padEsquerda;
    final plotTop = _padTopo;
    final plotWidth = (tamanho.width - _padEsquerda - _padDireita).clamp(1.0, double.infinity);
    final plotHeight = (tamanho.height - _padTopo - _padBase).clamp(1.0, double.infinity);

    var minimo = 50.0;
    var maximo = 110.0;
    final valores = <double>[];
    for (final p in serie.pontos) {
      valores.add(p.minimo);
      valores.add(p.maximo);
    }
    if (faixaRepouso != null) {
      valores.add(faixaRepouso.minimo);
      valores.add(faixaRepouso.maximo);
    }
    if (fcRepouso != null) valores.add(fcRepouso);

    if (valores.isNotEmpty) {
      minimo = valores.reduce((a, b) => a < b ? a : b);
      maximo = valores.reduce((a, b) => a > b ? a : b);
    }
    if ((maximo - minimo).abs() < 1e-6) {
      minimo -= 10;
      maximo += 10;
    }
    final span = maximo - minimo;
    final folga = span * 0.1;
    var yMin = minimo - folga;
    var yMax = maximo + folga;
    if (yMin < 0) yMin = 0;

    return _ChartGeometry(
      plotLeft: plotLeft,
      plotTop: plotTop,
      plotWidth: plotWidth,
      plotHeight: plotHeight,
      yMin: yMin,
      yMax: yMax,
    );
  }

  double x(DateTime inicioDoDia, DateTime t) {
    final minutos = t.difference(inicioDoDia).inMinutes.toDouble();
    final fracao = (minutos / (24 * 60)).clamp(0.0, 1.0);
    return plotLeft + fracao * plotWidth;
  }

  double y(double valor) {
    final fracao = ((valor - yMin) / (yMax - yMin)).clamp(0.0, 1.0);
    return plotTop + (1 - fracao) * plotHeight;
  }

  /// Ticks "redondos" (múltiplos de 10 ou 20 bpm) dentro de [yMin, yMax].
  List<double> tiquesY() {
    final span = yMax - yMin;
    final passo = span > 120 ? 20.0 : (span > 60 ? 20.0 : 10.0);
    final primeiro = (yMin / passo).ceil() * passo;
    final tiques = <double>[];
    for (var v = primeiro; v <= yMax + 1e-6; v += passo) {
      tiques.add(v);
    }
    if (tiques.length < 3) {
      // Domínio pequeno demais para o passo padrão: usa 3 pontos igualmente espaçados.
      return [yMin, (yMin + yMax) / 2, yMax];
    }
    if (tiques.length > 5) {
      return tiques.sublist(0, 5);
    }
    return tiques;
  }
}

class _DailyChartPainter extends CustomPainter {
  _DailyChartPainter({
    required this.serie,
    required this.agora,
    required this.faixaRepouso,
    required this.fcRepouso,
    required this.selecionado,
    required this.theme,
    required this.textScaler,
  });

  final SerieDia serie;
  final DateTime agora;
  final FaixaRepouso? faixaRepouso;
  final double? fcRepouso;
  final int selecionado;
  final ThemeData theme;
  final TextScaler textScaler;

  DateTime get _inicioDoDia => DateTime(serie.dia.year, serie.dia.month, serie.dia.day);

  @override
  void paint(Canvas canvas, Size size) {
    final scheme = theme.colorScheme;
    final geo = _ChartGeometry.calcular(size, serie, faixaRepouso, fcRepouso);
    final corAtividade = scheme.onSurfaceVariant.withValues(alpha: 0.6);
    final corTextoMudo = scheme.onSurfaceVariant;
    // Retângulos de rótulos já desenhados nesta pintura, para o rótulo seguinte se afastar em
    // vez de sobrepor texto a texto (ex.: "repouso NN" e o valor do vale, ambos perto do chão).
    final rotulosOcupados = <Rect>[];

    _desenharGradeY(canvas, geo, scheme, corTextoMudo);
    _desenharGradeX(canvas, geo, scheme, corTextoMudo);

    if (faixaRepouso != null) {
      _desenharFaixaRepouso(canvas, geo, scheme, corTextoMudo, rotulosOcupados);
    }
    if (fcRepouso != null) {
      _desenharFcRepouso(canvas, geo, scheme, corTextoMudo, rotulosOcupados);
    }

    if (serie.vazia) {
      _desenharTextoCentralizado(canvas, geo, scheme, 'Sem leituras hoje ainda', corTextoMudo);
      return;
    }

    _desenharAreaEDilha(canvas, geo, scheme, corAtividade);
    _desenharMarcadoresExtremos(canvas, geo, scheme, corAtividade, rotulosOcupados);
    _desenharUltimo(canvas, geo, scheme);

    if (selecionado >= 0 && selecionado < serie.pontos.length) {
      _desenharSelecao(canvas, geo, scheme, corTextoMudo, rotulosOcupados);
    }
  }

  /// Afasta [desejado] verticalmente (dentro dos limites do gráfico) até não sobrepor nenhum
  /// retângulo de [ocupados], tentando deslocamentos alternados para cima/baixo em passos
  /// crescentes; se nada couber sem colisão, cai de volta a um retângulo apenas grudado nos
  /// limites do gráfico (nunca clipa, mesmo que ainda toque outro rótulo).
  Rect _evitarColisao(Rect desejado, _ChartGeometry geo, List<Rect> ocupados) {
    const passo = 5.0;
    for (var tentativa = 0; tentativa < 24; tentativa++) {
      final deslocamento = ((tentativa + 1) ~/ 2) * passo * (tentativa.isEven ? 1 : -1);
      final candidato = desejado.translate(0, tentativa == 0 ? 0 : deslocamento);
      if (candidato.top >= geo.plotTop &&
          candidato.bottom <= geo.plotTop + geo.plotHeight &&
          !ocupados.any((r) => r.overlaps(candidato))) {
        ocupados.add(candidato);
        return candidato;
      }
    }
    var fallback = desejado;
    if (fallback.top < geo.plotTop) fallback = fallback.translate(0, geo.plotTop - fallback.top);
    if (fallback.bottom > geo.plotTop + geo.plotHeight) {
      fallback = fallback.translate(0, (geo.plotTop + geo.plotHeight) - fallback.bottom);
    }
    ocupados.add(fallback);
    return fallback;
  }

  void _desenharGradeY(Canvas canvas, _ChartGeometry geo, ColorScheme scheme, Color corTexto) {
    final paint = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1;
    for (final tique in geo.tiquesY()) {
      final y = geo.y(tique);
      canvas.drawLine(Offset(geo.plotLeft, y), Offset(geo.plotLeft + geo.plotWidth, y), paint);
      _desenharTexto(
        canvas,
        '${tique.round()}',
        theme.textTheme.bodySmall?.copyWith(color: corTexto),
        Offset(0, y),
        largura: geo.plotLeft - 4,
        alinhamento: Alignment.centerRight,
      );
    }
  }

  void _desenharGradeX(Canvas canvas, _ChartGeometry geo, ColorScheme scheme, Color corTexto) {
    final paint = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1;
    const horas = [0, 6, 12, 18, 24];
    for (final hora in horas) {
      final t = _inicioDoDia.add(Duration(hours: hora));
      final x = geo.x(_inicioDoDia, t);
      canvas.drawLine(Offset(x, geo.plotTop), Offset(x, geo.plotTop + geo.plotHeight), paint);
      final rotulo = '${hora.toString().padLeft(2, '0')}h';
      // 00h fica rente à esquerda da grade e 24h rente à direita, para nunca invadir a coluna
      // dos rótulos do eixo Y nem estourar a borda direita do gráfico; as horas do meio ficam
      // centradas na própria linha de grade.
      double caixaX;
      Alignment alinhamento;
      if (hora == 0) {
        caixaX = x;
        alinhamento = Alignment.centerLeft;
      } else if (hora == 24) {
        caixaX = x - 40;
        alinhamento = Alignment.centerRight;
      } else {
        caixaX = x - 20;
        alinhamento = Alignment.center;
      }
      _desenharTexto(
        canvas,
        rotulo,
        theme.textTheme.bodySmall?.copyWith(color: corTexto),
        Offset(caixaX, geo.plotTop + geo.plotHeight + 4),
        largura: 40,
        alinhamento: alinhamento,
      );
    }
  }

  void _desenharFaixaRepouso(
    Canvas canvas,
    _ChartGeometry geo,
    ColorScheme scheme,
    Color corTexto,
    List<Rect> rotulosOcupados,
  ) {
    final faixa = faixaRepouso!;
    final yTopo = geo.y(faixa.maximo);
    final yBase = geo.y(faixa.minimo);
    final retangulo = Rect.fromLTRB(geo.plotLeft, yTopo, geo.plotLeft + geo.plotWidth, yBase);
    final fundo = Paint()..color = scheme.primary.withValues(alpha: 0.08);
    canvas.drawRect(retangulo, fundo);
    final borda = Paint()
      ..color = scheme.primary.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(geo.plotLeft, yTopo), Offset(geo.plotLeft + geo.plotWidth, yTopo), borda);
    canvas.drawLine(Offset(geo.plotLeft, yBase), Offset(geo.plotLeft + geo.plotWidth, yBase), borda);

    if ((yBase - yTopo) >= 12) {
      final tp = _preparaTexto('linha de base', theme.textTheme.labelSmall?.copyWith(color: corTexto));
      final desejado = Rect.fromLTWH(
        geo.plotLeft + geo.plotWidth - 4 - tp.width,
        yTopo + (yBase - yTopo) / 2 - tp.height / 2,
        tp.width,
        tp.height,
      );
      final posicionado = _evitarColisao(desejado, geo, rotulosOcupados);
      tp.paint(canvas, posicionado.topLeft);
    }
  }

  void _desenharFcRepouso(
    Canvas canvas,
    _ChartGeometry geo,
    ColorScheme scheme,
    Color corTexto,
    List<Rect> rotulosOcupados,
  ) {
    final y = geo.y(fcRepouso!);
    final paint = Paint()
      ..color = scheme.onSurfaceVariant
      ..strokeWidth = 1;
    canvas.drawLine(Offset(geo.plotLeft, y), Offset(geo.plotLeft + geo.plotWidth, y), paint);
    final tp = _preparaTexto('repouso ${fcRepouso!.round()}', theme.textTheme.labelSmall?.copyWith(color: corTexto));
    final desejado = Rect.fromLTWH(geo.plotLeft + 4, y - 4 - tp.height, tp.width, tp.height);
    final posicionado = _evitarColisao(desejado, geo, rotulosOcupados);
    tp.paint(canvas, posicionado.topLeft);
  }

  void _desenharAreaEDilha(Canvas canvas, _ChartGeometry geo, ColorScheme scheme, Color corAtividade) {
    final pontos = serie.pontos;
    if (pontos.isEmpty) return;

    // Área sob os trechos de repouso, até o piso do gráfico (yMin), não até 0 bpm.
    final piso = geo.plotTop + geo.plotHeight;
    var emAreaAberta = false;
    Path? areaAtual;
    final areaPaint = Paint()..color = scheme.primary.withValues(alpha: 0.1);

    for (var i = 0; i < pontos.length; i++) {
      final ponto = pontos[i];
      final x = geo.x(_inicioDoDia, ponto.inicio);
      final y = geo.y(ponto.media);
      if (ponto.emRepouso) {
        if (!emAreaAberta) {
          areaAtual = Path()..moveTo(x, piso)..lineTo(x, y);
          emAreaAberta = true;
        } else {
          areaAtual!.lineTo(x, y);
        }
      } else if (emAreaAberta) {
        areaAtual!.lineTo(x, piso);
        areaAtual.close();
        canvas.drawPath(areaAtual, areaPaint);
        emAreaAberta = false;
        areaAtual = null;
      }
    }
    if (emAreaAberta && areaAtual != null) {
      final ultimoX = geo.x(_inicioDoDia, pontos.last.inicio);
      areaAtual.lineTo(ultimoX, piso);
      areaAtual.close();
      canvas.drawPath(areaAtual, areaPaint);
    }

    // Linha contínua 2px, colorindo cada segmento pelo estado do bloco de destino.
    final linhaRepouso = Paint()
      ..color = scheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final linhaAtividade = Paint()
      ..color = corAtividade
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < pontos.length - 1; i++) {
      final a = pontos[i];
      final b = pontos[i + 1];
      final p1 = Offset(geo.x(_inicioDoDia, a.inicio), geo.y(a.media));
      final p2 = Offset(geo.x(_inicioDoDia, b.inicio), geo.y(b.media));
      canvas.drawLine(p1, p2, b.emRepouso ? linhaRepouso : linhaAtividade);
    }
    if (pontos.length == 1) {
      final p = pontos.first;
      final offset = Offset(geo.x(_inicioDoDia, p.inicio), geo.y(p.media));
      canvas.drawCircle(offset, 3, Paint()..color = p.emRepouso ? scheme.primary : corAtividade);
    }
  }

  void _desenharMarcadoresExtremos(
    Canvas canvas,
    _ChartGeometry geo,
    ColorScheme scheme,
    Color corAtividade,
    List<Rect> rotulosOcupados,
  ) {
    final pico = serie.pico;
    final vale = serie.vale;
    if (pico != null) {
      _desenharMarcadorRotulado(
        canvas,
        geo,
        scheme,
        ponto: pico,
        valor: pico.maximo,
        preferirAcima: true,
        corAtividade: corAtividade,
        rotulosOcupados: rotulosOcupados,
      );
    }
    if (vale != null && vale != pico) {
      _desenharMarcadorRotulado(
        canvas,
        geo,
        scheme,
        ponto: vale,
        valor: vale.minimo,
        preferirAcima: false,
        corAtividade: corAtividade,
        rotulosOcupados: rotulosOcupados,
      );
    }
  }

  void _desenharMarcadorRotulado(
    Canvas canvas,
    _ChartGeometry geo,
    ColorScheme scheme, {
    required PontoSerieDia ponto,
    required double valor,
    required bool preferirAcima,
    required Color corAtividade,
    required List<Rect> rotulosOcupados,
  }) {
    final centro = Offset(geo.x(_inicioDoDia, ponto.inicio), geo.y(valor));
    final corMarcador = ponto.emRepouso ? scheme.primary : corAtividade;
    canvas.drawCircle(centro, 6, Paint()..color = scheme.surface);
    canvas.drawCircle(centro, 5, Paint()..color = corMarcador);

    final formatoHora = '${ponto.inicio.hour.toString().padLeft(2, '0')}:'
        '${ponto.inicio.minute.toString().padLeft(2, '0')}';
    final textoValor = '${valor.round()}';

    final tpValor = _preparaTexto(textoValor, theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    ));
    final tpHora = _preparaTexto(formatoHora, theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    ));

    // O rótulo ganha um "chip" (fundo da superfície + borda fina): sem ele, a grade horizontal e
    // a própria curva atravessavam o texto ("04:20" riscado pela linha dos 80 bpm).
    const folgaChip = 4.0;
    final larguraRotulo =
        [tpValor.width, tpHora.width].reduce((a, b) => a > b ? a : b) + folgaChip * 2;
    final alturaRotulo = tpValor.height + tpHora.height + folgaChip * 2;

    // Decide acima/abaixo para nunca clipar os limites do gráfico.
    var acima = preferirAcima;
    var y0 = acima ? centro.dy - 8 - alturaRotulo : centro.dy + 8;
    if (y0 < geo.plotTop) {
      acima = false;
      y0 = centro.dy + 8;
    } else if (y0 + alturaRotulo > geo.plotTop + geo.plotHeight) {
      acima = true;
      y0 = centro.dy - 8 - alturaRotulo;
    }

    var x0 = centro.dx - larguraRotulo / 2;
    if (x0 < geo.plotLeft) x0 = geo.plotLeft;
    if (x0 + larguraRotulo > geo.plotLeft + geo.plotWidth) x0 = geo.plotLeft + geo.plotWidth - larguraRotulo;

    // Afasta o grupo (valor + hora) de outros rótulos já desenhados (faixa de base, linha de
    // repouso), preservando a posição horizontal — só desliza verticalmente.
    final desejado = Rect.fromLTWH(x0, y0, larguraRotulo, alturaRotulo);
    final posicionado = _evitarColisao(desejado, geo, rotulosOcupados);
    final deslocamentoY = posicionado.top - y0;
    final yFinal = y0 + deslocamentoY;

    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(x0, yFinal, larguraRotulo, alturaRotulo),
      const Radius.circular(6),
    );
    canvas.drawRRect(chip, Paint()..color = scheme.surface);
    canvas.drawRRect(
      chip,
      Paint()
        ..color = scheme.outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tpValor.paint(
      canvas,
      Offset(x0 + (larguraRotulo - tpValor.width) / 2, yFinal + folgaChip),
    );
    tpHora.paint(
      canvas,
      Offset(x0 + (larguraRotulo - tpHora.width) / 2, yFinal + folgaChip + tpValor.height),
    );
  }

  void _desenharUltimo(Canvas canvas, _ChartGeometry geo, ColorScheme scheme) {
    final ultimo = serie.ultimo;
    if (ultimo == null) return;
    final centro = Offset(geo.x(_inicioDoDia, ultimo.inicio), geo.y(ultimo.media));
    canvas.drawCircle(centro, 4, Paint()..color = scheme.surface);
    canvas.drawCircle(centro, 3, Paint()..color = scheme.primary);
  }

  void _desenharSelecao(
    Canvas canvas,
    _ChartGeometry geo,
    ColorScheme scheme,
    Color corTexto,
    List<Rect> rotulosOcupados,
  ) {
    final ponto = serie.pontos[selecionado];
    final x = geo.x(_inicioDoDia, ponto.inicio);
    final paintLinha = Paint()
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x, geo.plotTop), Offset(x, geo.plotTop + geo.plotHeight), paintLinha);

    final formatoHora = '${ponto.inicio.hour.toString().padLeft(2, '0')}:'
        '${ponto.inicio.minute.toString().padLeft(2, '0')}';
    final linha1 = '$formatoHora · ${ponto.media.round()} bpm';
    final temFaixa = (ponto.maximo - ponto.minimo).round() != 0;
    final linha2 = temFaixa ? '${ponto.minimo.round()}–${ponto.maximo.round()} bpm' : null;

    final estiloLinha1 = theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurface);
    final estiloLinha2 = theme.textTheme.labelSmall?.copyWith(color: corTexto);
    final tp1 = _preparaTexto(linha1, estiloLinha1);
    final tp2 = linha2 != null ? _preparaTexto(linha2, estiloLinha2) : null;

    const paddingCaixa = 8.0;
    final larguraCaixa = [tp1.width, tp2?.width ?? 0].reduce((a, b) => a > b ? a : b) + paddingCaixa * 2;
    final alturaCaixa = tp1.height + (tp2?.height ?? 0) + paddingCaixa * 2;

    var caixaX = x + 8;
    if (caixaX + larguraCaixa > geo.plotLeft + geo.plotWidth) {
      caixaX = x - 8 - larguraCaixa;
    }
    if (caixaX < geo.plotLeft) caixaX = geo.plotLeft;

    // No topo por padrão; se cobrir o rótulo do pico/vale, desce para o pé do gráfico (o tooltip
    // é passageiro, os rótulos dos extremos são o que a pessoa veio ver).
    var caixaY = geo.plotTop + 4;
    Rect caixa() => Rect.fromLTWH(caixaX, caixaY, larguraCaixa, alturaCaixa);
    if (rotulosOcupados.any((r) => r.overlaps(caixa()))) {
      final noPe = geo.plotTop + geo.plotHeight - alturaCaixa - 4;
      final caixaNoPe = Rect.fromLTWH(caixaX, noPe, larguraCaixa, alturaCaixa);
      if (!rotulosOcupados.any((r) => r.overlaps(caixaNoPe))) caixaY = noPe;
    }
    final retangulo = RRect.fromRectAndRadius(
      Rect.fromLTWH(caixaX, caixaY, larguraCaixa, alturaCaixa),
      const Radius.circular(8),
    );
    canvas.drawRRect(retangulo, Paint()..color = scheme.surface);
    canvas.drawRRect(
      retangulo,
      Paint()
        ..color = scheme.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tp1.paint(canvas, Offset(caixaX + paddingCaixa, caixaY + paddingCaixa));
    tp2?.paint(canvas, Offset(caixaX + paddingCaixa, caixaY + paddingCaixa + tp1.height));
  }

  void _desenharTextoCentralizado(Canvas canvas, _ChartGeometry geo, ColorScheme scheme, String texto, Color cor) {
    final tp = _preparaTexto(texto, theme.textTheme.bodyMedium?.copyWith(color: cor),
        larguraMaxima: geo.plotWidth);
    final offset = Offset(
      geo.plotLeft + (geo.plotWidth - tp.width) / 2,
      geo.plotTop + (geo.plotHeight - tp.height) / 2,
    );
    // Fundo sólido atrás do texto: sem isso, a gridline horizontal do meio corta o texto ao
    // meio e prejudica a leitura.
    const folga = 6.0;
    final fundo = RRect.fromRectAndRadius(
      Rect.fromLTWH(offset.dx - folga, offset.dy - folga, tp.width + folga * 2, tp.height + folga * 2),
      const Radius.circular(6),
    );
    canvas.drawRRect(fundo, Paint()..color = scheme.surface);
    tp.paint(canvas, offset);
  }

  TextPainter _preparaTexto(String texto, TextStyle? estilo, {double? larguraMaxima}) {
    final tp = TextPainter(
      text: TextSpan(text: texto, style: estilo),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    );
    tp.layout(maxWidth: larguraMaxima ?? double.infinity);
    return tp;
  }

  void _desenharTexto(
    Canvas canvas,
    String texto,
    TextStyle? estilo,
    Offset posicao, {
    required double largura,
    Alignment alinhamento = Alignment.centerLeft,
  }) {
    final tp = _preparaTexto(texto, estilo, larguraMaxima: largura);
    var dx = posicao.dx;
    if (alinhamento == Alignment.centerRight) {
      dx = posicao.dx + largura - tp.width;
    } else if (alinhamento == Alignment.center) {
      dx = posicao.dx + (largura - tp.width) / 2;
    }
    tp.paint(canvas, Offset(dx, posicao.dy));
  }

  @override
  bool shouldRepaint(covariant _DailyChartPainter oldDelegate) {
    return oldDelegate.serie != serie ||
        oldDelegate.agora != agora ||
        oldDelegate.faixaRepouso != faixaRepouso ||
        oldDelegate.fcRepouso != fcRepouso ||
        oldDelegate.selecionado != selecionado ||
        oldDelegate.theme != theme ||
        oldDelegate.textScaler != textScaler;
  }
}

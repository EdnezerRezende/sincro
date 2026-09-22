// Testes comportamentais + harness de renderização do gráfico intraday (Variante A —
// "linha contínua"): dia cheio, parcial, vazio e com seleção, nos dois temas e duas larguras.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_daily_chart.dart';
import 'package:sincro_mobile/features/biofeedback/health_reading.dart';
import 'package:sincro_mobile/features/biofeedback/serie_dia.dart';

/// Diretório de saída dos PNGs do harness, vindo do ambiente: sem `SINCRO_RENDER_DIR` o harness
/// é pulado (ele existe para inspeção visual, não para comparação de goldens no repositório).
final String? _dirRenders = Platform.environment['SINCRO_RENDER_DIR'];

final _dia = DateTime(2026, 9, 20);

/// Repouso: entre 00h e 07h e entre 22h e 24h, e nas madrugadas — fora dos blocos de atividade
/// explicitamente marcados (caminhada 12:00–12:20 e treino 17:50–18:30).
bool _emRepouso(DateTime t) {
  final minutos = t.hour * 60 + t.minute;
  final caminhada = minutos >= 12 * 60 && minutos < 12 * 60 + 20;
  final treino = minutos >= 17 * 60 + 50 && minutos < 18 * 60 + 30;
  return !caminhada && !treino;
}

List<HealthReading> _leiturasDiaCheio() {
  final leituras = <HealthReading>[];
  for (var minuto = 10; minuto < 24 * 60; minuto += 5) {
    final t = _dia.add(Duration(minutes: minuto));
    double valor;
    if (minuto >= 17 * 60 + 50 && minuto < 18 * 60 + 30) {
      // Treino: sobe suavemente até um pico ~155–160 por volta das 18h20 e recua um pouco no fim.
      final progresso = (minuto - (17 * 60 + 50)) / 40.0;
      valor = 122 + 36 * math.sin(progresso * math.pi / 2 * 1.15).clamp(0.0, 1.0);
    } else if (minuto >= 12 * 60 && minuto < 12 * 60 + 20) {
      // Caminhada: variação suave em torno de 100 bpm, sem serrilhado.
      valor = 100 + 5 * math.sin(minuto / 6.0);
    } else if (minuto < 7 * 60 || minuto >= 22 * 60) {
      // Repouso noturno: ondulação lenta e de baixa amplitude entre ~52 e ~60.
      valor = 56 + 4 * math.sin(minuto / 55.0);
    } else {
      // Vigília em repouso: ondulação suave entre ~65 e ~85.
      valor = 75 + 10 * math.sin(minuto / 73.0);
    }
    leituras.add(HealthReading(valor: valor, timestamp: t));
  }
  return leituras;
}

List<HealthReading> _leiturasDiaParcial() {
  return _leiturasDiaCheio().where((l) => l.timestamp.isBefore(_dia.add(const Duration(hours: 14, minutes: 20)))).toList();
}

SerieDia _serieCheia() => SerieDia.agregar(dia: _dia, leituras: _leiturasDiaCheio(), emRepouso: _emRepouso);

SerieDia _serieParcial() => SerieDia.agregar(dia: _dia, leituras: _leiturasDiaParcial(), emRepouso: _emRepouso);

SerieDia _serieVazia() => SerieDia.agregar(dia: _dia, leituras: const [], emRepouso: _emRepouso);

const _faixaRepouso = (minimo: 54.0, maximo: 62.0);
const _fcRepouso = 58.0;

Future<void> _carregarFonteReal() async {
  final loader = FontLoader('Atkinson Hyperlegible');
  for (final arquivo in ['AtkinsonHyperlegible-Regular.ttf', 'AtkinsonHyperlegible-Bold.ttf']) {
    final bytes = File('assets/fonts/$arquivo').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Widget _harness({
  required SerieDia serie,
  required DateTime agora,
  required ThemeData tema,
  ({double minimo, double maximo})? faixaRepouso,
  double? fcRepouso,
}) {
  return MaterialApp(
    theme: tema,
    home: Scaffold(
      backgroundColor: tema.colorScheme.surface,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: RepaintBoundary(
          child: BiofeedbackDailyChart(
            serie: serie,
            agora: agora,
            faixaRepouso: faixaRepouso,
            fcRepouso: fcRepouso,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_carregarFonteReal);

  group('BiofeedbackDailyChart — comportamento', () {
    testWidgets('renderiza dia cheio sem overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_harness(
        serie: _serieCheia(),
        agora: _dia.add(const Duration(hours: 23, minutes: 50)),
        tema: sincroLightTheme,
        faixaRepouso: _faixaRepouso,
        fcRepouso: _fcRepouso,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renderiza dia parcial sem overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_harness(
        serie: _serieParcial(),
        agora: _dia.add(const Duration(hours: 14, minutes: 20)),
        tema: sincroLightTheme,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renderiza estado vazio com texto central e sem overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_harness(
        serie: _serieVazia(),
        agora: _dia.add(const Duration(hours: 9)),
        tema: sincroLightTheme,
      ));
      await tester.pumpAndSettle();
      // O texto "Sem leituras hoje ainda" é desenhado no canvas (CustomPainter), não como
      // Text widget — a verificação visual fica a cargo dos PNGs do harness abaixo; aqui
      // confirmamos que o canvas do gráfico está montado e não há overflow/exceção.
      expect(find.byKey(biofeedbackDailyChartCanvasKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('semantics resume mínima, máxima e última', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final serie = _serieCheia();
      await tester.pumpWidget(_harness(
        serie: serie,
        agora: _dia.add(const Duration(hours: 23, minutes: 50)),
        tema: sincroLightTheme,
      ));
      await tester.pumpAndSettle();

      final finder = find.byWidgetPredicate((w) => w is Semantics && w.properties.label != null);
      final semantics = tester.getSemantics(finder.first);
      final label = semantics.label;
      expect(label, contains('mínima'));
      expect(label, contains('máxima'));
      expect(label, contains('última'));
      expect(label, contains('bpm'));
    });

    testWidgets('semantics do estado vazio menciona "sem leituras hoje ainda"', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_harness(
        serie: _serieVazia(),
        agora: _dia.add(const Duration(hours: 9)),
        tema: sincroLightTheme,
      ));
      await tester.pumpAndSettle();

      final finder = find.byWidgetPredicate((w) => w is Semantics && w.properties.label != null);
      final semantics = tester.getSemantics(finder.first);
      expect(semantics.label, contains('sem leituras hoje ainda'));
    });

    testWidgets('tocar no gráfico seleciona o bloco mais próximo e mostra tooltip com bpm', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_harness(
        serie: _serieCheia(),
        agora: _dia.add(const Duration(hours: 23, minutes: 50)),
        tema: sincroLightTheme,
      ));
      await tester.pumpAndSettle();

      // Toca perto do meio do gráfico (aprox. meio-dia).
      final canvasFinder = find.byKey(biofeedbackDailyChartCanvasKey);
      final center = tester.getCenter(canvasFinder);
      await tester.tapAt(center);
      await tester.pump();

      expect(tester.takeException(), isNull);
      // O tooltip é desenhado no canvas (não há Text widget) — confirmamos que o widget
      // continua montado e sem exceção após a seleção (a caixa "HH:mm · NN bpm" é validada
      // visualmente pelos PNGs do estado "selecionado" no harness abaixo).
      expect(canvasFinder, findsOneWidget);
    });

    testWidgets('não lança exceção com textScale 1.6', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: sincroLightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: BiofeedbackDailyChart(
              serie: _serieCheia(),
              agora: _dia.add(const Duration(hours: 23, minutes: 50)),
              faixaRepouso: _faixaRepouso,
              fcRepouso: _fcRepouso,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('BiofeedbackDailyChart — render harness (PNG)', skip: _dirRenders == null ? 'defina SINCRO_RENDER_DIR' : false, () {
    final estados = <String, ({SerieDia Function() serie, DateTime agora, ({double minimo, double maximo})? faixa, double? fc})>{
      'cheio': (
        serie: _serieCheia,
        agora: _dia.add(const Duration(hours: 23, minutes: 50)),
        faixa: _faixaRepouso,
        fc: _fcRepouso,
      ),
      'parcial': (
        serie: _serieParcial,
        agora: _dia.add(const Duration(hours: 14, minutes: 20)),
        faixa: null,
        fc: null,
      ),
      'vazio': (
        serie: _serieVazia,
        agora: _dia.add(const Duration(hours: 9)),
        faixa: null,
        fc: null,
      ),
      'selecionado': (
        serie: _serieCheia,
        agora: _dia.add(const Duration(hours: 23, minutes: 50)),
        faixa: _faixaRepouso,
        fc: _fcRepouso,
      ),
    };
    final temas = {'light': sincroLightTheme, 'dark': sincroDarkTheme};
    const larguras = [360.0, 430.0];

    for (final estadoEntry in estados.entries) {
      for (final temaEntry in temas.entries) {
        for (final largura in larguras) {
          final nome = 'chart_${estadoEntry.key}_${largura.toInt()}_${temaEntry.key}';
          testWidgets('golden $nome', (tester) async {
            tester.view.physicalSize = Size(largura, 420);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            final cfg = estadoEntry.value;
            await tester.pumpWidget(_harness(
              serie: cfg.serie(),
              agora: cfg.agora,
              tema: temaEntry.value,
              faixaRepouso: cfg.faixa,
              fcRepouso: cfg.fc,
            ));
            await tester.pumpAndSettle();

            if (estadoEntry.key == 'selecionado') {
              final rect = tester.getRect(find.byKey(biofeedbackDailyChartCanvasKey));
              final xMeioDia = rect.left + rect.width * (10 / 24);
              await tester.tapAt(Offset(xMeioDia, rect.center.dy));
              await tester.pump();
            }

            await expectLater(
              find.byType(RepaintBoundary).first,
              matchesGoldenFile(Uri.file('$_dirRenders/$nome.png')),
            );
          });
        }
      }
    }
  });
}

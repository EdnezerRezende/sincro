// Harness de renderização da tela de Biofeedback (PNG) para inspeção visual: duas larguras, dois
// temas e os estados com dados / coletando / sem série / erro. Pulado sem `SINCRO_RENDER_DIR`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_providers.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_screen.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';
import 'package:sincro_mobile/features/biofeedback/health_reading.dart';
import 'package:sincro_mobile/features/biofeedback/linha_de_base.dart';
import 'package:sincro_mobile/features/biofeedback/serie_dia.dart';

final String? _dir = Platform.environment['SINCRO_RENDER_DIR'];

Future<void> _carregarFonteReal() async {
  final loader = FontLoader('Atkinson Hyperlegible');
  for (final arquivo in ['AtkinsonHyperlegible-Regular.ttf', 'AtkinsonHyperlegible-Bold.ttf']) {
    final bytes = File('assets/fonts/$arquivo').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

SerieDia _serieRealista(DateTime hoje) {
  DateTime t(int h, int m) => DateTime(hoje.year, hoje.month, hoje.day, h, m);
  final leituras = <HealthReading>[];
  for (var min = 0; min < 24 * 60 - 5; min += 5) {
    final h = min ~/ 60;
    double v;
    if (h < 6) {
      v = 54 + (min % 30 == 0 ? 3 : 0);
    } else if (h >= 12 && min < 12 * 60 + 20) {
      v = 98 + (min % 10);
    } else if (min >= 17 * 60 + 50 && min < 18 * 60 + 30) {
      v = 120 + (min - (17 * 60 + 50)) * 1.0;
    } else if (h >= 22) {
      v = 62;
    } else {
      v = 70 + ((min ~/ 5) % 4) * 3;
    }
    leituras.add(HealthReading(valor: v, timestamp: t(h, min % 60)));
  }
  return SerieDia.agregar(
    dia: hoje,
    leituras: leituras,
    emRepouso: (ts) {
      final min = ts.hour * 60 + ts.minute;
      final andando = min >= 12 * 60 && min < 12 * 60 + 20;
      final treino = min >= 17 * 60 + 50 && min < 18 * 60 + 30;
      return !andando && !treino;
    },
  );
}

Widget _app({
  required ThemeData theme,
  required BiofeedbackSummary? resumo,
  SerieDia? serie,
  int dias = 0,
  bool erro = false,
}) {
  return ProviderScope(
    overrides: [
      biofeedbackResumoProvider.overrideWith(
        (ref) async => erro ? throw Exception('falha simulada') : resumo,
      ),
      biofeedbackSerieDiaProvider.overrideWith((ref) async => serie),
      biofeedbackDiasNoHistoricoProvider.overrideWith((ref) async => dias),
      biofeedbackPermissaoProvider.overrideWith((ref) async => true),
    ],
    child: MaterialApp(theme: theme, home: const BiofeedbackScreen()),
  );
}

void main() {
  setUpAll(_carregarFonteReal);

  group('BiofeedbackScreen — render harness (PNG)',
      skip: _dir == null ? 'defina SINCRO_RENDER_DIR' : false, () {
    final hoje = DateTime.now();
    DateTime as_(int h, int m) => DateTime(hoje.year, hoje.month, hoje.day, h, m);
    final serie = _serieRealista(hoje);

    final completo = BiofeedbackSummary(
      ultimaFc: 62,
      ultimaFcEm: as_(23, 50),
      mediaFcHoje: 64,
      mediaVfcHoje: null,
      fcRepousoNativa: 56,
      fcRepousoNativaEm: as_(6, 30),
      fcMinHoje: serie.minimo,
      fcMaxHoje: serie.maximo,
      linhaDeBase: const LinhaDeBase(dias: 13, fcMedia: 63, fcDesvio: 2.5),
      usaVfc: false,
      estadoEstresse: EstadoEstresse.calmo,
      atualizadoEm: as_(23, 52),
    );
    final elevado = BiofeedbackSummary(
      ultimaFc: 78,
      ultimaFcEm: as_(15, 10),
      mediaFcHoje: 74,
      mediaVfcHoje: 31,
      fcRepousoNativa: 66,
      fcRepousoNativaEm: as_(7, 0),
      fcMinHoje: 58,
      fcMaxHoje: 142,
      linhaDeBase: const LinhaDeBase(dias: 14, fcMedia: 63, fcDesvio: 2.5, vfcMedia: 48, vfcDesvio: 6),
      usaVfc: true,
      estadoEstresse: EstadoEstresse.elevado,
      atualizadoEm: as_(15, 12),
    );
    final coletando = BiofeedbackSummary(
      ultimaFc: 70,
      ultimaFcEm: as_(10, 5),
      mediaFcHoje: 68,
      mediaVfcHoje: 54,
      fcMinHoje: 55,
      fcMaxHoje: 101,
      estadoEstresse: EstadoEstresse.coletandoDados,
      atualizadoEm: as_(10, 6),
    );
    final semSerie = BiofeedbackSummary(
      ultimaFc: null,
      mediaFcHoje: null,
      mediaVfcHoje: null,
      estadoEstresse: EstadoEstresse.coletandoDados,
      atualizadoEm: as_(8, 0),
    );

    final cenarios = <String, ({BiofeedbackSummary? resumo, SerieDia? serie, int dias, bool erro})>{
      'completo': (resumo: completo, serie: serie, dias: 13, erro: false),
      'elevado': (resumo: elevado, serie: serie, dias: 14, erro: false),
      'coletando': (resumo: coletando, serie: serie, dias: 4, erro: false),
      'sem_serie': (resumo: semSerie, serie: null, dias: 0, erro: false),
      'erro': (resumo: null, serie: null, dias: 0, erro: true),
    };

    for (final entry in cenarios.entries) {
      for (final largura in [360.0, 430.0]) {
        for (final theme in [sincroLightTheme, sincroDarkTheme]) {
          final nome = 'screen_${entry.key}_${largura.toInt()}_${theme.brightness.name}';
          testWidgets(nome, (tester) async {
            tester.view.physicalSize = Size(largura, 1180);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);
            final c = entry.value;
            await tester.pumpWidget(_app(
              theme: theme,
              resumo: c.resumo,
              serie: c.serie,
              dias: c.dias,
              erro: c.erro,
            ));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(Uri.file('$_dir/$nome.png')),
            );
          });
        }
      }
    }
  });
}

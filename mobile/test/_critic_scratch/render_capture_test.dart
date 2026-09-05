// GAUNTLET CRITIC SCRATCH HARNESS - not part of the product. Deleted after the run.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/email_triage/email_summary.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/inbox_screen.dart';

const outDir =
    '/private/tmp/claude-501/-Users-ed-Desenvolvimento-projetos-sincro/a881a664-f682-4abd-8c41-05fdfd296d49/scratchpad/shots';

final report = <String, dynamic>{};

double _lin(double c) {
  c = c / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _lum(Color c) =>
    0.2126 * _lin((c.r * 255).roundToDouble()) +
    0.7152 * _lin((c.g * 255).roundToDouble()) +
    0.0722 * _lin((c.b * 255).roundToDouble());

double contrast(Color a, Color b) {
  final l1 = _lum(a), l2 = _lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

Color over(Color fg, Color bg) {
  final a = fg.a;
  return Color.fromARGB(
    255,
    ((fg.r * a + bg.r * (1 - a)) * 255).round(),
    ((fg.g * a + bg.g * (1 - a)) * 255).round(),
    ((fg.b * a + bg.b * (1 - a)) * 255).round(),
  );
}

Future<void> loadFonts() async {
  for (final f in [
    'assets/fonts/AtkinsonHyperlegible-Regular.ttf',
    'assets/fonts/AtkinsonHyperlegible-Bold.ttf',
  ]) {
    final loader = FontLoader('Atkinson Hyperlegible');
    loader.addFont(Future.value(File(f).readAsBytesSync().buffer.asByteData()));
    await loader.load();
  }
  // Material icons so Icon() renders glyphs, not tofu.
  final iconFile = File(
      '/opt/homebrew/Caskroom/flutter/*/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (iconFile.existsSync()) {
    final l = FontLoader('MaterialIcons');
    l.addFont(Future.value(iconFile.readAsBytesSync().buffer.asByteData()));
    await l.load();
  }
}

final now = DateTime(2026, 9, 5, 14, 30);

List<EmailSummary> sample() => [
      EmailSummary(
        id: '1',
        remetente: 'Dra. Helena Marques',
        assunto: 'Confirmação da consulta de terça-feira',
        resumoCurto:
            'Sua consulta está marcada para terça às 15h. Responda confirmando ou peça para remarcar.',
        categoria: 'PRECISA_ATENCAO',
        recebidoEm: now.subtract(const Duration(minutes: 12)),
      ),
      EmailSummary(
        id: '2',
        remetente: 'Banco Inter',
        assunto: 'Fatura do cartão fecha em 3 dias',
        resumoCurto: 'O valor parcial é R\$ 412,90. O vencimento é dia 12.',
        categoria: 'PRECISA_ATENCAO',
        recebidoEm: now.subtract(const Duration(hours: 5)),
      ),
      EmailSummary(
        id: '3',
        remetente: 'contato+newsletter-de-produtividade-semanal@exemplo-muito-longo.com.br',
        assunto:
            'Um assunto propositalmente longo para provar que o truncamento com reticências funciona mesmo em 390px',
        resumoCurto:
            'Um resumo bem longo que deve quebrar em duas linhas e depois truncar com reticências, para verificar o comportamento de overflow em telas estreitas sem estourar o layout nem gerar overflow amarelo.',
        categoria: 'PODE_ESPERAR',
        recebidoEm: now.subtract(const Duration(days: 1)),
      ),
      EmailSummary(
        id: '4',
        remetente: 'Netflix',
        assunto: 'Novidades da semana',
        resumoCurto: 'Novos títulos adicionados ao catálogo.',
        categoria: 'PODE_ESPERAR',
        recebidoEm: now.subtract(const Duration(days: 20)),
      ),
    ];

Widget harness(ThemeData theme, Future<List<EmailSummary>> Function() src) => ProviderScope(
      overrides: [emailSummariesProvider.overrideWith((ref) => src())],
      child: MaterialApp(theme: theme, home: const InboxScreen(), debugShowCheckedModeBanner: false),
    );

Future<void> shoot(WidgetTester tester, String name) async {
  final boundary =
      tester.binding.renderViewElement!.findRenderObject()! as RenderObject;
  RenderRepaintBoundary? rb;
  void walk(RenderObject o) {
    if (rb != null) return;
    if (o is RenderRepaintBoundary) { rb = o; return; }
    o.visitChildren(walk);
  }
  walk(boundary);
  final img = await rb!.toImage(pixelRatio: 2.0);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  // raw pixels for contrast sampling
  final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  File('$outDir/$name.rgba').writeAsBytesSync(raw!.buffer.asUint8List());
  report['${name}_size'] = '${img.width}x${img.height}';
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
    Directory(outDir).createSync(recursive: true);
  });

  tearDownAll(() {
    File('$outDir/report.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  });

  for (final w in [390.0, 1440.0]) {
    for (final entry in {'light': sincroLightTheme, 'dark': sincroDarkTheme}.entries) {
      testWidgets('data ${w.toInt()} ${entry.key}', (tester) async {
        final h = w == 390.0 ? 844.0 : 900.0;
        await tester.binding.setSurfaceSize(Size(w, h));
        tester.view.physicalSize = Size(w * 2, h * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(harness(
          entry.value,
          () async => sample(),
        ));
        await tester.pumpAndSettle();
        final ex = tester.takeException();
        report['exception_data_${w.toInt()}_${entry.key}'] = ex?.toString() ?? 'NONE';
        await shoot(tester, 'data_${w.toInt()}_${entry.key}');
      });
    }
  }

  for (final entry in {'light': sincroLightTheme, 'dark': sincroDarkTheme}.entries) {
    testWidgets('empty ${entry.key}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(
        entry.value,
        () async => <EmailSummary>[],
      ));
      await tester.pumpAndSettle();
      report['exception_empty_${entry.key}'] = tester.takeException()?.toString() ?? 'NONE';
      await shoot(tester, 'empty_${entry.key}');
    });

    testWidgets('loading ${entry.key}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(
        entry.value,
        () => Future.delayed(
            const Duration(seconds: 30), () => <EmailSummary>[]),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      report['exception_loading_${entry.key}'] = tester.takeException()?.toString() ?? 'NONE';
      await shoot(tester, 'loading_${entry.key}');
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('error ${entry.key}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(
        entry.value,
        () async => throw Exception('boom-forced'),
      ));
      await tester.pumpAndSettle();
      report['exception_error_${entry.key}'] = tester.takeException()?.toString() ?? 'NONE';
      await shoot(tester, 'error_${entry.key}');
    });
  }
}

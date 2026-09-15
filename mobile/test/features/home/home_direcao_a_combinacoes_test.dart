// Direção A em TODAS as combinações da Home (2 layouts × 3 estilos) e nos dois temas:
// a estrutura é a mesma — saudação, cartão de destaque de Finanças, cartões agrupados
// (`SectionCard`) e rodapé de emergência fixo, alcançável sem rolar — e nenhuma cor
// hard-coded quebra o tema escuro (renderiza sem exceção nos dois temas).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/core/widgets/section_card.dart';
import 'package:sincro_mobile/core/widgets/section_row.dart';
import 'package:sincro_mobile/core/widgets/tonal_panel.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/finance_summary.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';
import 'package:sincro_mobile/features/home/home_design_style.dart';
import 'package:sincro_mobile/features/home/home_layout_mode.dart';
import 'package:sincro_mobile/features/home/home_providers.dart';
import 'package:sincro_mobile/features/home/home_screen.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contact.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';

List<Override> _overrides(HomeLayoutMode modo, HomeDesignStyle design, {bool gmailConectado = true}) => [
      homeLayoutModeProvider.overrideWith((ref) async => modo),
      homeDesignStyleProvider.overrideWith((ref) async => design),
      upcomingEventsProvider.overrideWith((ref) async => <CalendarEvent>[]),
      biofeedbackAtivoProvider.overrideWith((ref) async => false),
      gmailConnectionStatusProvider.overrideWith(
        (ref) async => gmailConectado
            ? const GmailConnectionStatus(connected: true, gmailEmail: 'ana@exemplo.com')
            : const GmailConnectionStatus(connected: false),
      ),
      financeSummaryProvider.overrideWith((ref) async => FinanceSummary(
            saldoLivre: 1240,
            saldoContas: 0,
            faturasAbertas: 0,
            despesasPendentesCiclo: 0,
            cicloFim: DateTime.utc(2026, 10, 4),
          )),
      lancamentosPendentesProvider.overrideWith((ref) async => <LancamentoFinanceiro>[]),
      trustedContactsListProvider.overrideWith((ref) async => const [
            TrustedContact(id: 'c1', nome: 'Marina', relacao: 'FAMILIAR', whatsapp: '+5511999990000', prioridade: 0),
          ]),
    ];

Future<void> _pump(
  WidgetTester tester,
  HomeLayoutMode modo,
  HomeDesignStyle design,
  ThemeData theme, {
  double textScale = 1.0,
  bool gmailConectado = true,
}) async {
  // Viewport de celular (prancha 390×844) para validar "emergência alcançável sem rolar".
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(modo, design, gmailConectado: gmailConectado),
    child: MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const HomeScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Carrega a Atkinson Hyperlegible real: com a fonte de teste (Ahem, glifos quadrados de 1 em)
/// toda medida de texto sai inflada e as asserções de geometria abaixo não dizem nada sobre o
/// app de verdade.
Future<void> _carregarFonteReal() async {
  final loader = FontLoader('Atkinson Hyperlegible');
  for (final arquivo in ['AtkinsonHyperlegible-Regular.ttf', 'AtkinsonHyperlegible-Bold.ttf']) {
    final bytes = File('assets/fonts/$arquivo').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(_carregarFonteReal);

  for (final modo in HomeLayoutMode.values) {
    for (final design in HomeDesignStyle.values) {
      group('Home direção A (${modo.name}/${design.name})', () {
        testWidgets('tem saudação, destaque de Finanças, cartões agrupados e emergência fixa', (tester) async {
          await _pump(tester, modo, design, sincroLightTheme);

          expect(find.text('Você está em dia'), findsOneWidget);
          expect(find.text('Tudo sob controle'), findsOneWidget);
          expect(find.text('Saldo Livre'), findsOneWidget);
          expect(find.textContaining('1.240,00'), findsOneWidget);
          expect(find.text('Ver finanças'), findsOneWidget);
          expect(find.byType(TonalPanel), findsOneWidget);
          // Nas abas só a aba "Hoje" está montada; no resumo os dois grupos aparecem juntos.
          expect(find.byType(SectionCard), modo == HomeLayoutMode.resumo ? findsNWidgets(2) : findsOneWidget);
          expect(find.text('Caixa de Entrada'), findsOneWidget);
          expect(find.text('Próximos eventos'), findsOneWidget);
          expect(find.text('Biofeedback'), findsOneWidget);

          // Nada de "Finanças" repetido como título: o cartão se identifica pelo saldo.
          expect(find.text('Finanças'), findsNothing);

          // Emergência sempre alcançável, sem rolar, dentro da tela.
          final button = find.text('Avisar Rede de Apoio');
          expect(button, findsOneWidget);
          final rect = tester.getRect(button);
          expect(rect.bottom, lessThanOrEqualTo(844));
          expect(rect.top, greaterThan(0));
        });

        testWidgets('renderiza sem exceção no tema escuro', (tester) async {
          await _pump(tester, modo, design, sincroDarkTheme);
          expect(tester.takeException(), isNull);
          expect(find.text('Você está em dia'), findsOneWidget);
          expect(find.text('Avisar Rede de Apoio'), findsOneWidget);
        });
      });
    }
  }

  testWidgets('nas abas, "Apoio" mostra os dois atalhos e a emergência continua visível', (tester) async {
    await _pump(tester, HomeLayoutMode.abas, HomeDesignStyle.moderno, sincroLightTheme);
    await tester.tap(find.widgetWithText(Tab, 'Apoio'));
    await tester.pumpAndSettle();
    expect(find.text('Encontrar profissional'), findsOneWidget);
    expect(find.text('Alívio sensorial'), findsOneWidget);
    expect(find.text('Avisar Rede de Apoio'), findsOneWidget);
  });

  testWidgets('Funcional Direto nomeia os grupos e mostra o status do dia', (tester) async {
    await _pump(tester, HomeLayoutMode.resumo, HomeDesignStyle.funcional, sincroLightTheme);
    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text('Apoio'), findsOneWidget);
    expect(find.text('Status do dia'), findsOneWidget);
    expect(find.text('Monitoramento inativo'), findsOneWidget);
    // Traço do estilo: só o dado, sem prosa.
    expect(find.text('ana@exemplo.com'), findsOneWidget);
  });

  // Geometria — o que "presença de texto" não pega: ritmo das linhas e abas com altura real.
  for (final design in HomeDesignStyle.values) {
    testWidgets('linhas dos cartões mantêm o ritmo da direção A (${design.name})', (tester) async {
      await _pump(tester, HomeLayoutMode.resumo, design, sincroLightTheme, gmailConectado: false);
      final alturas = tester.widgetList(find.byType(SectionRow)).map((w) {
        return tester.getSize(find.byWidget(w)).height;
      }).toList();
      expect(alturas, isNotEmpty);
      // 56 dp de base (48 em dense): subtítulo de uma linha → 61, de duas → 82, de três → 103
      // (o pior caso da própria prancha, Biofeedback inativo com ação); nunca às 164–185 dp
      // medidas quando o botão de uma linha esmagava a coluna de texto.
      for (final h in alturas) {
        expect(h, lessThanOrEqualTo(104), reason: 'linha de $h dp em ${design.name}');
      }
      // O título não pode quebrar: cada título ocupa uma linha só.
      final titulo = tester.renderObject<RenderParagraph>(find.text('Biofeedback'));
      expect(titulo.size.height, lessThanOrEqualTo(28));
      // A tela inteira cabe em 844 sem rolar quando há contatos (spec).
      expect(tester.getRect(find.text('Alívio sensorial')).bottom, lessThan(844 - 72));
    });
  }

  for (final design in HomeDesignStyle.values) {
    testWidgets('abas com texto em 2,0× continuam mostrando o conteúdo (${design.name})', (tester) async {
      await _pump(tester, HomeLayoutMode.abas, design, sincroLightTheme, textScale: 2.0);
      expect(tester.takeException(), isNull);
      // Em 2,0× o cabeçalho (saudação + destaque) passa da altura da tela: rola até o conteúdo
      // da aba "Hoje" e confere que ele existe e tem altura real (antes ficava em 390×0).
      await tester.scrollUntilVisible(find.text('Caixa de Entrada'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Caixa de Entrada'), findsOneWidget);
      expect(tester.getSize(find.byType(TabBarView)).height, greaterThan(0));
      expect(find.text('Avisar Rede de Apoio'), findsOneWidget);
    });
  }

  testWidgets('cabeçalho traz o logo e a wordmark, e o CTA de emergência ocupa a largura toda', (tester) async {
    await _pump(tester, HomeLayoutMode.resumo, HomeDesignStyle.minimalista, sincroLightTheme);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Sincro'), findsOneWidget);
    final cta = tester.getRect(find.widgetWithText(ElevatedButton, 'Avisar Rede de Apoio'));
    expect(cta.width, greaterThanOrEqualTo(390 - 2 * 20 - 1));
    expect(cta.height, greaterThanOrEqualTo(56));
  });
}

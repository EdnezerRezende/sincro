// Finanças deve sempre ser o primeiro item, único acima das abas: um card fixo com Saldo Livre
// e "Ver finanças", nunca mais uma aba disputando espaço com as outras seções.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
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
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';

LancamentoFinanceiro _pendente(String id) {
  return LancamentoFinanceiro(
    id: id,
    tipo: TipoLancamento.despesa,
    descricao: 'Pendente $id',
    instituicao: 'Nubank',
    valor: 100,
    dataVencimento: DateTime.utc(2026, 9, 20),
    dataCompetencia: DateTime.utc(2026, 9, 20),
    status: StatusLancamento.pendenteRevisao,
    origem: OrigemLancamento.emailParser,
    isPago: false,
    codigoBarras: null,
    cartaoId: null,
    contaId: null,
  );
}

Widget _app({
  required HomeDesignStyle design,
  List<LancamentoFinanceiro> pendentes = const [],
}) {
  return ProviderScope(
    overrides: [
      homeLayoutModeProvider.overrideWith((ref) async => HomeLayoutMode.abas),
      homeDesignStyleProvider.overrideWith((ref) async => design),
      upcomingEventsProvider.overrideWith((ref) async => <CalendarEvent>[]),
      biofeedbackAtivoProvider.overrideWith((ref) async => false),
      gmailConnectionStatusProvider.overrideWith(
        (ref) async => const GmailConnectionStatus(connected: false),
      ),
      financeSummaryProvider.overrideWith(
        (ref) async => FinanceSummary(
          saldoLivre: 1234.56,
          saldoContas: 1234.56,
          faturasAbertas: 0,
          despesasPendentesCiclo: 0,
          cicloFim: DateTime.utc(2026, 9, 30),
        ),
      ),
      lancamentosPendentesProvider.overrideWith((ref) async => pendentes),
      trustedContactsListProvider.overrideWith((ref) async => []),
    ],
    child: MaterialApp(theme: sincroLightTheme, home: const HomeScreen()),
  );
}

void main() {
  for (final design in HomeDesignStyle.values) {
    group('Abas layout Finanças placement (${design.name})', () {
      testWidgets('Finanças is a fixed card above the tabs, not a tab of its own', (
        tester,
      ) async {
        await tester.pumpWidget(_app(design: design));
        await tester.pumpAndSettle();

        // Não é mais uma aba: só "Hoje" e "Apoio".
        expect(find.widgetWithText(Tab, 'Hoje'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Apoio'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Finanças'), findsNothing);

        // O card fixo mostra o saldo livre sem precisar trocar de aba.
        expect(find.textContaining('1.234,56'), findsOneWidget);
        expect(find.textContaining('Ver finanças'), findsOneWidget);

        // Continua acessível a partir de qualquer aba.
        await tester.tap(find.widgetWithText(Tab, 'Apoio'));
        await tester.pumpAndSettle();
        expect(find.textContaining('1.234,56'), findsOneWidget);
      });

      testWidgets('o card fixo ocupa a largura cheia em vez de ficar centralizado', (
        tester,
      ) async {
        await tester.pumpWidget(_app(design: design));
        await tester.pumpAndSettle();

        // Guarda de regressão: a Column externa do layout Abas deixava de definir
        // crossAxisAlignment (caindo no padrão center), o que encolhia o card fixo ao seu
        // tamanho intrínseco e o centralizava em vez de ocupar a largura cheia como no
        // Resumo Simples.
        //
        // O finder sobe a árvore a partir do texto "Ver finanças", presente nos três estilos,
        // até o Padding mais externo que o envolve — o Padding do card em si (com o
        // fromLTRB(16/14/12, ..., 0) da view Abas), não "o primeiro Padding da árvore":
        // `find.byType(Padding).first` já se mostrou frágil a um Padding inserido antes na
        // árvore (por exemplo dentro do MaterialApp/Scaffold), que faria a guarda medir o
        // widget errado e continuar verde mesmo com uma regressão real.
        //
        // A asserção compara contra a borda exata da tela (não um percentual solto): sem o
        // `crossAxisAlignment: stretch`, o Padding encolhe ao conteúdo e fica centralizado,
        // então `topLeft.dx` deixaria de ser ~0 e `bottomRight.dx` deixaria de ser
        // ~larguraDaTela. Isso é uma guarda real (comprovada rodando os testes contra o código
        // anterior ao fix) para o Minimalista, cujo card é uma Column simples sem Expanded
        // interno. Já no Moderno e no Funcional, o conteúdo do card usa Row+Expanded, que por
        // si só já ocupa a largura máxima disponível independente do alinhamento da Column
        // externa — nesses dois estilos a asserção continua verdadeira e serve como
        // documentação/estabilidade, mas não é capaz de detectar sozinha a remoção do
        // `stretch` (a única guarda que discriminaria os três seria assertar o
        // `crossAxisAlignment` da Column diretamente, o que é detalhe de implementação).
        final cardPadding = find.ancestor(
          of: find.textContaining('Ver finanças'),
          matching: find.byType(Padding),
        );
        final rect = tester.getRect(cardPadding.last);
        final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
        expect(rect.left, closeTo(0, 1.0));
        expect(rect.right, closeTo(screenWidth, 1.0));
      });

      testWidgets('não repete o título redundante "Finanças" acima do saldo', (
        tester,
      ) async {
        await tester.pumpWidget(_app(design: design));
        await tester.pumpAndSettle();

        // O card já se identifica como Finanças via "Ver finanças" e o saldo em si — o
        // título "Finanças" isolado é retirado neste layout. Um `Semantics(label: ...)`
        // continua anunciando "Finanças" para leitura por voz mesmo sem o texto visível
        // (ver `_FinancasCard.showTitle` em home_screen.dart).
        expect(find.text('Finanças'), findsNothing);
      });

      testWidgets('o rótulo de acessibilidade inclui a contagem de pendências, não só o saldo', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          _app(design: design, pendentes: [_pendente('a'), _pendente('b')]),
        );
        await tester.pumpAndSettle();

        // Regressão: `Semantics(excludeSemantics: true)` substitui TODO o conteúdo anunciado
        // do card pelo `label` — sem incluir a contagem de pendências ali, a linha "2
        // lançamentos para revisar, sem pressa", que continua visível na tela, desaparecia da
        // leitura por voz.
        expect(find.textContaining('para revisar'), findsOneWidget);
        final semanticsData = tester.getSemantics(
          find.ancestor(
            of: find.textContaining('Ver finanças'),
            matching: find.byType(Semantics),
          ).first,
        );
        expect(semanticsData.label, contains('Finanças'));
        expect(semanticsData.label, contains('para revisar'));
        handle.dispose();
      });
    });
  }
}

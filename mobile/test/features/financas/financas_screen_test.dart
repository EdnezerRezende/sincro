import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/finance_summary.dart';
import 'package:sincro_mobile/features/financas/finance_summary_repository.dart';
import 'package:sincro_mobile/features/financas/financas_screen.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';
import 'package:sincro_mobile/features/financas/lancamentos_repository.dart';

class _FakeFinanceSummaryRepository extends FinanceSummaryRepository {
  _FakeFinanceSummaryRepository(this._summary) : super(Dio());
  final FinanceSummary _summary;
  @override
  Future<FinanceSummary> getResumo() async => _summary;
}

class _FakeLancamentosRepository extends LancamentosRepository {
  _FakeLancamentosRepository({required this.pendentes, required this.doMes})
    : super(Dio());
  final List<LancamentoFinanceiro> pendentes;
  final List<LancamentoFinanceiro> doMes;
  String? lastRemovedId;

  @override
  Future<List<LancamentoFinanceiro>> list({String? status, String? mes}) async {
    if (status == 'PENDENTE_REVISAO') return pendentes;
    return doMes;
  }

  @override
  Future<void> remove(String id) async {
    lastRemovedId = id;
  }
}

final _summaryVazio = FinanceSummary(
  saldoLivre: 1000,
  saldoContas: 1000,
  faturasAbertas: 0,
  despesasPendentesCiclo: 0,
  cicloFim: DateTime.utc(2026, 9, 30),
);

LancamentoFinanceiro _pendente({required String descricao, double? valor}) {
  return LancamentoFinanceiro(
    id: 'l-$descricao',
    tipo: TipoLancamento.despesa,
    descricao: descricao,
    instituicao: 'Nubank',
    valor: valor,
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

/// Factory genérica para os testes de filtro/ordenação/badges — permite controlar
/// `id` (desempate determinístico), `tipo`, `valor` e `dataVencimento` livremente.
LancamentoFinanceiro _lancamento({
  required String id,
  required String descricao,
  TipoLancamento tipo = TipoLancamento.despesa,
  double? valor,
  DateTime? dataVencimento,
}) {
  final data = dataVencimento ?? DateTime.utc(2026, 9, 20);
  return LancamentoFinanceiro(
    id: id,
    tipo: tipo,
    descricao: descricao,
    instituicao: null,
    valor: valor,
    dataVencimento: data,
    dataCompetencia: data,
    status: StatusLancamento.pendenteRevisao,
    origem: OrigemLancamento.emailParser,
    isPago: false,
    codigoBarras: null,
    cartaoId: null,
    contaId: null,
  );
}

/// Abre o dropdown de ordenação e seleciona a opção com o texto [label].
Future<void> _selecionarOrdenacao(WidgetTester tester, String label) async {
  await tester.tap(find.byWidgetPredicate((w) => w is DropdownButton));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Percorre a árvore real de semântica (via `SemanticsOwner`, não `find.bySemanticsLabel`
/// isoladamente) e devolve o label de cada nó não vazio — usado para provar isolamento
/// e mesclagem corretos entre cards, badges e legendas (regressão do bug em que cards
/// adjacentes colapsavam num único nó e o badge de tipo virava nó irmão solto).
List<String> _semanticsLabels(WidgetTester tester) {
  final root = tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }
  visit(root);
  return labels;
}

Widget _app({
  required List<LancamentoFinanceiro> pendentes,
  required List<LancamentoFinanceiro> doMes,
  _FakeLancamentosRepository? repository,
}) {
  return ProviderScope(
    overrides: [
      financeSummaryRepositoryProvider.overrideWithValue(
        _FakeFinanceSummaryRepository(_summaryVazio),
      ),
      lancamentosRepositoryProvider.overrideWithValue(
        repository ?? _FakeLancamentosRepository(pendentes: pendentes, doMes: doMes),
      ),
    ],
    child: MaterialApp(theme: sincroLightTheme, home: const FinancasScreen()),
  );
}

void main() {
  testWidgets('tapping the + action opens NovoLancamentoScreen', (tester) async {
    await tester.pumpWidget(_app(pendentes: const [], doMes: const []));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Novo lançamento'), findsOneWidget);
  });

  testWidgets('shows the Saldo Livre value from the summary', (tester) async {
    await tester.pumpWidget(_app(pendentes: const [], doMes: const []));
    await tester.pumpAndSettle();

    expect(find.textContaining('1.000,00'), findsOneWidget);
  });

  testWidgets('defaults to the "Lançamentos do mês" tab, not Pendentes', (tester) async {
    await tester.pumpWidget(
      _app(
        pendentes: [_pendente(descricao: 'Pendente A')],
        doMes: [_pendente(descricao: 'Confirmado B')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirmado B'), findsOneWidget);
    expect(find.text('Pendente A'), findsNothing);
  });

  testWidgets('the Pendentes chip shows the pending count, 0 when there are none', (tester) async {
    await tester.pumpWidget(_app(pendentes: const [], doMes: const []));
    await tester.pumpAndSettle();

    expect(find.text('Pendentes de revisão (0)'), findsOneWidget);
  });

  testWidgets('the Pendentes chip shows the pending count when there are pendências', (tester) async {
    await tester.pumpWidget(
      _app(
        pendentes: [
          _pendente(descricao: 'A'),
          _pendente(descricao: 'B'),
          _pendente(descricao: 'C'),
        ],
        doMes: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pendentes de revisão (3)'), findsOneWidget);
  });

  testWidgets('switching to "Pendentes de revisão" shows pending lançamentos instead', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        pendentes: [_pendente(descricao: 'Pendente A')],
        doMes: [_pendente(descricao: 'Confirmado B')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Pendentes de revisão'));
    await tester.pumpAndSettle();

    expect(find.text('Pendente A'), findsOneWidget);
    expect(find.text('Confirmado B'), findsNothing);
  });

  testWidgets('shows "informar valor" instead of a value when valor is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        pendentes: [_pendente(descricao: 'Conta de luz', valor: null)],
        doMes: const [],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pendentes de revisão'));
    await tester.pumpAndSettle();

    expect(find.text('informar valor'), findsOneWidget);
  });

  testWidgets(
    'shows the instituicao as a badge next to the pending lançamento',
    (tester) async {
      await tester.pumpWidget(
        _app(
          pendentes: [_pendente(descricao: 'Fatura Nubank', valor: 512.40)],
          doMes: const [],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Pendentes de revisão'));
      await tester.pumpAndSettle();

      expect(find.text('Nubank'), findsOneWidget);
    },
  );

  testWidgets('tapping Revisar opens the confirmation sheet', (tester) async {
    await tester.pumpWidget(
      _app(
        pendentes: [_pendente(descricao: 'Fatura Nubank', valor: 512.40)],
        doMes: const [],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pendentes de revisão'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmar lançamento'), findsOneWidget);
  });

  testWidgets('tapping the edit icon on a "do mês" card opens it pre-filled for editing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(pendentes: const [], doMes: [_pendente(descricao: 'Aluguel', valor: 1450)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Editar lançamento'), findsOneWidget);
    expect(find.text('Aluguel'), findsOneWidget);
  });

  testWidgets('tapping the delete icon and confirming removes the lançamento', (tester) async {
    final repository = _FakeLancamentosRepository(
      pendentes: const [],
      doMes: [_pendente(descricao: 'Aluguel', valor: 1450)],
    );
    await tester.pumpWidget(_app(pendentes: const [], doMes: const [], repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Excluir'));
    await tester.pumpAndSettle();

    expect(repository.lastRemovedId, 'l-Aluguel');
  });

  group('filtro de tipo', () {
    testWidgets('Todas/Entradas/Despesas funciona em "Lançamentos do mês"', (tester) async {
      await tester.pumpWidget(
        _app(
          pendentes: const [],
          doMes: [
            _lancamento(id: 'd1', descricao: 'Aluguel', tipo: TipoLancamento.despesa),
            _lancamento(id: 'r1', descricao: 'Salário', tipo: TipoLancamento.receita),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Todas (padrão): os dois aparecem.
      expect(find.text('Aluguel'), findsOneWidget);
      expect(find.text('Salário'), findsOneWidget);

      await tester.tap(find.text('Entradas'));
      await tester.pumpAndSettle();
      expect(find.text('Salário'), findsOneWidget);
      expect(find.text('Aluguel'), findsNothing);

      await tester.tap(find.text('Despesas'));
      await tester.pumpAndSettle();
      expect(find.text('Aluguel'), findsOneWidget);
      expect(find.text('Salário'), findsNothing);

      await tester.tap(find.text('Todas'));
      await tester.pumpAndSettle();
      expect(find.text('Aluguel'), findsOneWidget);
      expect(find.text('Salário'), findsOneWidget);
    });

    testWidgets('Todas/Entradas/Despesas funciona em "Pendentes de revisão"', (tester) async {
      await tester.pumpWidget(
        _app(
          pendentes: [
            _lancamento(id: 'd1', descricao: 'Fatura Nubank', tipo: TipoLancamento.despesa),
            _lancamento(id: 'r1', descricao: 'Reembolso', tipo: TipoLancamento.receita),
          ],
          doMes: const [],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Pendentes de revisão'));
      await tester.pumpAndSettle();

      expect(find.text('Fatura Nubank'), findsOneWidget);
      expect(find.text('Reembolso'), findsOneWidget);

      await tester.tap(find.text('Entradas'));
      await tester.pumpAndSettle();
      expect(find.text('Reembolso'), findsOneWidget);
      expect(find.text('Fatura Nubank'), findsNothing);

      await tester.tap(find.text('Despesas'));
      await tester.pumpAndSettle();
      expect(find.text('Fatura Nubank'), findsOneWidget);
      expect(find.text('Reembolso'), findsNothing);
    });

    testWidgets(
      'filtro "Despesas" inclui faturaCartao junto com despesa (mesmo agrupamento binário)',
      (tester) async {
        await tester.pumpWidget(
          _app(
            pendentes: const [],
            doMes: [
              _lancamento(id: 'r1', descricao: 'Salário', tipo: TipoLancamento.receita),
              _lancamento(id: 'd1', descricao: 'Aluguel', tipo: TipoLancamento.despesa),
              _lancamento(id: 'f1', descricao: 'Fatura Cartão', tipo: TipoLancamento.faturaCartao),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Despesas'));
        await tester.pumpAndSettle();

        expect(find.text('Aluguel'), findsOneWidget);
        expect(find.text('Fatura Cartão'), findsOneWidget);
        expect(find.text('Salário'), findsNothing);
      },
    );
  });

  group('ordenação', () {
    testWidgets('"Data ↑" ordena por dataVencimento crescente', (tester) async {
      await tester.pumpWidget(
        _app(
          pendentes: const [],
          doMes: [
            _lancamento(
              id: 'c',
              descricao: 'Terceiro',
              dataVencimento: DateTime.utc(2026, 9, 25),
            ),
            _lancamento(
              id: 'a',
              descricao: 'Primeiro',
              dataVencimento: DateTime.utc(2026, 9, 5),
            ),
            _lancamento(
              id: 'b',
              descricao: 'Segundo',
              dataVencimento: DateTime.utc(2026, 9, 15),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Ordenação padrão já é "Data ↑" (vencimento crescente).
      final yPrimeiro = tester.getTopLeft(find.text('Primeiro')).dy;
      final ySegundo = tester.getTopLeft(find.text('Segundo')).dy;
      final yTerceiro = tester.getTopLeft(find.text('Terceiro')).dy;
      expect(yPrimeiro, lessThan(ySegundo));
      expect(ySegundo, lessThan(yTerceiro));
    });

    testWidgets('"Valor ↓" ordena do maior para o menor', (tester) async {
      await tester.pumpWidget(
        _app(
          pendentes: const [],
          doMes: [
            _lancamento(id: 'a', descricao: 'Baixo', valor: 10),
            _lancamento(id: 'b', descricao: 'Alto', valor: 900),
            _lancamento(id: 'c', descricao: 'Médio', valor: 400),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _selecionarOrdenacao(tester, 'Valor ↓');

      final yAlto = tester.getTopLeft(find.text('Alto')).dy;
      final yMedio = tester.getTopLeft(find.text('Médio')).dy;
      final yBaixo = tester.getTopLeft(find.text('Baixo')).dy;
      expect(yAlto, lessThan(yMedio));
      expect(yMedio, lessThan(yBaixo));
    });

    testWidgets('"Tipo" agrupa receitas antes de despesas/faturas', (tester) async {
      await tester.pumpWidget(
        _app(
          pendentes: const [],
          doMes: [
            _lancamento(
              id: 'r',
              descricao: 'Uma Receita',
              tipo: TipoLancamento.receita,
              dataVencimento: DateTime.utc(2026, 9, 10),
            ),
            _lancamento(
              id: 'd',
              descricao: 'Uma Despesa',
              tipo: TipoLancamento.despesa,
              dataVencimento: DateTime.utc(2026, 9, 10),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _selecionarOrdenacao(tester, 'Tipo');

      final yReceita = tester.getTopLeft(find.text('Uma Receita')).dy;
      final yDespesa = tester.getTopLeft(find.text('Uma Despesa')).dy;
      expect(yReceita, lessThan(yDespesa));
    });

    testWidgets(
      '"Tipo" agrupa faturaCartao junto com despesa (mesmo grupo binário do filtro)',
      (tester) async {
        await tester.pumpWidget(
          _app(
            pendentes: const [],
            doMes: [
              _lancamento(
                id: 'r',
                descricao: 'Uma Receita',
                tipo: TipoLancamento.receita,
                dataVencimento: DateTime.utc(2026, 9, 10),
              ),
              _lancamento(
                id: 'f',
                descricao: 'Uma Fatura',
                tipo: TipoLancamento.faturaCartao,
                dataVencimento: DateTime.utc(2026, 9, 10),
              ),
              _lancamento(
                id: 'd',
                descricao: 'Uma Despesa',
                tipo: TipoLancamento.despesa,
                dataVencimento: DateTime.utc(2026, 9, 12),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await _selecionarOrdenacao(tester, 'Tipo');

        final yReceita = tester.getTopLeft(find.text('Uma Receita')).dy;
        final yFatura = tester.getTopLeft(find.text('Uma Fatura')).dy;
        final yDespesa = tester.getTopLeft(find.text('Uma Despesa')).dy;
        // Receita isolada num grupo antes; faturaCartao e despesa no mesmo grupo
        // (ambos depois da receita), respeitando o mesmo agrupamento binário do
        // filtro "Despesas" (que já inclui despesa+faturaCartao).
        expect(yReceita, lessThan(yFatura));
        expect(yReceita, lessThan(yDespesa));
      },
    );

    testWidgets(
      'empate no critério de ordenação (data) é resolvido deterministicamente por id, com 40+ itens, '
      'em qualquer ordem de entrada',
      (tester) async {
        // 45 lançamentos com a MESMA dataVencimento — desempate só pelo `id`. A ordem
        // final deve ser idêntica não importa em que ordem a lista chega da API.
        final mesmaData = DateTime.utc(2026, 9, 20);
        final base = List.generate(
          45,
          (i) => _lancamento(
            id: 'id-${i.toString().padLeft(3, '0')}',
            descricao: 'Item ${i.toString().padLeft(3, '0')}',
            dataVencimento: mesmaData,
          ),
        );
        final ordemCrescente = List<LancamentoFinanceiro>.from(base);
        final ordemDecrescente = List<LancamentoFinanceiro>.from(base.reversed);
        final ordemEmbaralhada = List<LancamentoFinanceiro>.from(base)..shuffle(Random(7));

        Future<List<String>> ordemRenderizada(List<LancamentoFinanceiro> entrada) async {
          await tester.pumpWidget(_app(pendentes: const [], doMes: entrada));
          await tester.pumpAndSettle();
          final posicoes = <String, double>{};
          for (final item in base) {
            posicoes[item.descricao] = tester.getTopLeft(find.text(item.descricao)).dy;
          }
          final ordenados = posicoes.keys.toList()
            ..sort((a, b) => posicoes[a]!.compareTo(posicoes[b]!));
          return ordenados;
        }

        final resultadoA = await ordemRenderizada(ordemCrescente);
        final resultadoB = await ordemRenderizada(ordemDecrescente);
        final resultadoC = await ordemRenderizada(ordemEmbaralhada);

        // Todas as permutações de entrada produzem a MESMA ordem final na tela — prova
        // de que o `sort` não depende da ordem de chegada (Dart `List.sort` não é
        // estável, então sem desempate por `id` isso poderia variar entre execuções).
        expect(resultadoB, equals(resultadoA));
        expect(resultadoC, equals(resultadoA));
        // E a ordem é a esperada: por `id` ascendente (id-000, id-001, ...).
        expect(
          resultadoA,
          equals(base.map((l) => l.descricao).toList()),
        );
      },
    );
  });

  group('badge de tipo', () {
    testWidgets('mostra seta para cima em receitas e para baixo em despesas ("do mês")', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          pendentes: const [],
          doMes: [
            _lancamento(id: 'r', descricao: 'Salário', tipo: TipoLancamento.receita),
            _lancamento(id: 'd', descricao: 'Aluguel', tipo: TipoLancamento.despesa),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

      // O badge não é mais um nó de semântica isolado (isso o deixava "solto", sem
      // vínculo com o lançamento) — seu label agora se mescla no nó do card ancestral.
      // Por isso não usamos mais `find.bySemanticsLabel('Receita')` com igualdade
      // exata: verificamos que o rótulo está CONTIDO no nó do card correspondente.
      final labels = _semanticsLabels(tester);
      final nodeReceita = labels.firstWhere(
        (l) => l.contains('Salário'),
        orElse: () => '',
      );
      final nodeDespesa = labels.firstWhere(
        (l) => l.contains('Aluguel'),
        orElse: () => '',
      );
      expect(nodeReceita, isNotEmpty, reason: 'nó de semântica do card "Salário" deve existir');
      expect(nodeDespesa, isNotEmpty, reason: 'nó de semântica do card "Aluguel" deve existir');
      expect(nodeReceita, contains('Receita'));
      expect(nodeDespesa, contains('Despesa'));
      semantics.dispose();
    });

    testWidgets('mostra seta para cima em receitas e para baixo em despesas (pendentes)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          pendentes: [
            _lancamento(id: 'r', descricao: 'Reembolso', tipo: TipoLancamento.receita),
            _lancamento(id: 'd', descricao: 'Fatura', tipo: TipoLancamento.despesa),
          ],
          doMes: const [],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Pendentes de revisão'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

      // Gap 7(d): o badge semântico também precisa ser verificado na aba Pendentes, não
      // só em "Lançamentos do mês" — o card dessa aba (`_LancamentoPendenteCard`) é uma
      // classe diferente, com seu próprio `Semantics(container: true)`.
      final labels = _semanticsLabels(tester);
      final nodeReceita = labels.firstWhere(
        (l) => l.contains('Reembolso'),
        orElse: () => '',
      );
      final nodeDespesa = labels.firstWhere(
        (l) => l.contains('Fatura'),
        orElse: () => '',
      );
      expect(nodeReceita, isNotEmpty);
      expect(nodeDespesa, isNotEmpty);
      expect(nodeReceita, contains('Receita'));
      expect(nodeDespesa, contains('Despesa'));
      semantics.dispose();
    });
  });

  group('semântica dos cards (regressão: cards colapsando num nó compartilhado)', () {
    testWidgets(
      'cada card de "Lançamentos do mês" é um nó de semântica isolado — descrições não vazam entre cards adjacentes',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            pendentes: const [],
            doMes: [
              _lancamento(id: 'a1', descricao: 'Aluguel', tipo: TipoLancamento.despesa, valor: 1450),
              _lancamento(id: 's1', descricao: 'Salario', tipo: TipoLancamento.receita, valor: 5000),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final labels = _semanticsLabels(tester);

        // (a)+(b) "Salario" e "Aluguel" continuam alcançáveis como nós próprios — seja via
        // `find.bySemanticsLabel` com regex (substring), seja contidos no label do card.
        expect(find.bySemanticsLabel(RegExp('Salario')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Aluguel')), findsOneWidget);

        final nodeSalario = labels.firstWhere((l) => l.contains('Salario'), orElse: () => '');
        final nodeAluguel = labels.firstWhere((l) => l.contains('Aluguel'), orElse: () => '');
        expect(nodeSalario, isNotEmpty);
        expect(nodeAluguel, isNotEmpty);

        // (c) o rótulo de tipo está DENTRO do mesmo nó do lançamento que descreve — não é
        // um nó irmão solto sem vínculo.
        expect(nodeSalario, contains('Receita'));
        expect(nodeAluguel, contains('Despesa'));

        // Isolamento: nenhum nó mistura as descrições dos dois lançamentos diferentes —
        // é exatamente o bug relatado (cards colapsando num nó compartilhado).
        expect(nodeSalario, isNot(contains('Aluguel')));
        expect(nodeAluguel, isNot(contains('Salario')));
        expect(nodeSalario, isNot(equals(nodeAluguel)));

        // Não deve existir nenhum nó "Receita"/"Despesa" solto (label exatamente igual a
        // isso, sem mais nada) — seria o badge órfão relatado no bug original.
        expect(labels, isNot(contains('Receita')));
        expect(labels, isNot(contains('Despesa')));

        semantics.dispose();
      },
    );

    testWidgets(
      '"Filtrar por tipo" e o dropdown de ordenação ficam em nós de semântica distintos',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(_app(pendentes: const [], doMes: const []));
        await tester.pumpAndSettle();

        final labels = _semanticsLabels(tester);
        final nodeFiltro = labels.firstWhere(
          (l) => l.contains('Filtrar por tipo'),
          orElse: () => '',
        );
        final nodeOrdenar = labels.firstWhere(
          (l) => l.contains('Ordenar') && l.contains('Data'),
          orElse: () => '',
        );

        expect(nodeFiltro, isNotEmpty);
        expect(nodeOrdenar, isNotEmpty);
        // Antes do fix, um leitor de tela anunciava o dropdown de ORDENAÇÃO como se fosse
        // o filtro de TIPO porque os dois se fundiam num único nó.
        expect(nodeFiltro, isNot(equals(nodeOrdenar)));
        expect(nodeFiltro, isNot(contains('Data')));
        expect(nodeOrdenar, isNot(contains('Filtrar por tipo')));

        semantics.dispose();
      },
    );
  });

  group('layout do dropdown de ordenação em telas estreitas', () {
    // Captura real mostrou "Ordenar: Data (mai…" truncado em 390 dp. Testa em três
    // larguras de celular comuns (320 = iPhone SE 1ª/2ª geração, 360 = Android médio,
    // 390 = iPhone 12/13/14) que nenhum dos três valores possíveis do dropdown trunca.
    for (final width in [320.0, 360.0, 390.0]) {
      testWidgets('nenhum valor do dropdown trunca em largura $width', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(pendentes: const [], doMes: const []));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        void expectSemOverflow(String label) {
          final elements = find.text(label).evaluate();
          expect(
            elements,
            isNotEmpty,
            reason: 'texto "$label" deveria estar visível em largura $width',
          );
          for (final element in elements) {
            final renderObject = element.renderObject;
            if (renderObject is RenderParagraph) {
              expect(
                renderObject.didExceedMaxLines,
                isFalse,
                reason: '"$label" truncou (ellipsis) em largura $width',
              );
            }
          }
        }

        expectSemOverflow('Data ↑'); // valor padrão
        await _selecionarOrdenacao(tester, 'Valor ↓');
        expectSemOverflow('Valor ↓');
        await _selecionarOrdenacao(tester, 'Tipo');
        expectSemOverflow('Tipo');
        expectSemOverflow('Filtrar por tipo');
      });
    }
  });

  group('estado vazio', () {
    testWidgets('aparece quando o filtro não retorna nada e permite limpar o filtro', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          pendentes: const [],
          doMes: [_lancamento(id: 'd', descricao: 'Aluguel', tipo: TipoLancamento.despesa)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Entradas'));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum lançamento encontrado'), findsOneWidget);
      expect(find.text('Aluguel'), findsNothing);

      await tester.tap(find.text('Limpar filtro'));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum lançamento encontrado'), findsNothing);
      expect(find.text('Aluguel'), findsOneWidget);
    });

    testWidgets('aparece em "Pendentes de revisão" quando o filtro não retorna nada', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          pendentes: [_lancamento(id: 'r', descricao: 'Reembolso', tipo: TipoLancamento.receita)],
          doMes: const [],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Pendentes de revisão'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Despesas'));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum lançamento encontrado'), findsOneWidget);
    });
  });
}

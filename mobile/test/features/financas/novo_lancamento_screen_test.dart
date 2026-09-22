import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/financas/cartao_credito.dart';
import 'package:sincro_mobile/features/financas/cartoes_repository.dart';
import 'package:sincro_mobile/features/financas/conta_financeira.dart';
import 'package:sincro_mobile/features/financas/contas_repository.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';
import 'package:sincro_mobile/features/financas/lancamentos_repository.dart';
import 'package:sincro_mobile/features/financas/novo_lancamento_screen.dart';

class _FakeContasRepository extends ContasRepository {
  _FakeContasRepository([this._contas = const []]) : super(Dio());
  final List<ContaFinanceira> _contas;
  @override
  Future<List<ContaFinanceira>> list() async => _contas;
}

class _FakeCartoesRepository extends CartoesRepository {
  _FakeCartoesRepository() : super(Dio());
  @override
  Future<List<CartaoCredito>> list() async => const [];
}

class _FakeLancamentosRepository extends LancamentosRepository {
  _FakeLancamentosRepository() : super(Dio());
  Map<String, dynamic>? lastCreateArgs;
  Map<String, dynamic>? lastUpdateArgs;
  Map<String, dynamic>? lastConfirmarArgs;
  String? lastRemovedId;
  bool shouldFail = false;
  bool shouldFailConfirmar = false;
  int confirmarCallCount = 0;

  /// Quando não-nulo, `update()` espera por este future antes de responder — usado para
  /// simular uma requisição em voo e testar o que acontece se a tela for desmontada antes
  /// da resposta chegar (item 2 do crítico).
  Future<void>? gateDoUpdate;

  @override
  Future<List<LancamentoFinanceiro>> list({
    String? status,
    String? mes,
  }) async => const [];

  @override
  Future<LancamentoFinanceiro> create({
    required TipoLancamento tipo,
    required String descricao,
    required DateTime dataVencimento,
    double? valor,
    String? instituicao,
    DateTime? dataCompetencia,
    String? contaId,
    String? cartaoId,
    bool? isPago,
  }) async {
    if (shouldFail) {
      throw DioException(
        requestOptions: RequestOptions(path: '/financas/lancamentos'),
      );
    }
    lastCreateArgs = {
      'tipo': tipo,
      'descricao': descricao,
      'dataVencimento': dataVencimento,
      'valor': valor,
      'contaId': contaId,
      'cartaoId': cartaoId,
      'isPago': isPago,
    };
    return LancamentoFinanceiro(
      id: 'novo-1',
      tipo: tipo,
      descricao: descricao,
      instituicao: instituicao,
      valor: valor,
      dataVencimento: dataVencimento,
      dataCompetencia: dataVencimento,
      status: StatusLancamento.confirmado,
      origem: OrigemLancamento.manual,
      isPago: isPago ?? false,
      codigoBarras: null,
      cartaoId: cartaoId,
      contaId: contaId,
    );
  }

  @override
  Future<LancamentoFinanceiro> update(
    String id, {
    TipoLancamento? tipo,
    String? descricao,
    DateTime? dataVencimento,
    double? valor,
    String? instituicao,
    DateTime? dataCompetencia,
    String? contaId,
    String? cartaoId,
    bool? isPago,
  }) async {
    if (gateDoUpdate != null) await gateDoUpdate;
    if (shouldFail) {
      throw DioException(
        requestOptions: RequestOptions(path: '/financas/lancamentos/$id'),
      );
    }
    lastUpdateArgs = {
      'id': id,
      'tipo': tipo,
      'descricao': descricao,
      'valor': valor,
      'dataVencimento': dataVencimento,
      'isPago': isPago,
    };
    return LancamentoFinanceiro(
      id: id,
      tipo: tipo ?? TipoLancamento.despesa,
      descricao: descricao ?? '',
      instituicao: instituicao,
      valor: valor,
      dataVencimento: dataVencimento ?? DateTime.now(),
      dataCompetencia: dataVencimento ?? DateTime.now(),
      status: StatusLancamento.confirmado,
      origem: OrigemLancamento.manual,
      isPago: isPago ?? false,
      codigoBarras: null,
      cartaoId: cartaoId,
      contaId: contaId,
    );
  }

  @override
  Future<void> remove(String id) async {
    if (shouldFail) {
      throw DioException(
        requestOptions: RequestOptions(path: '/financas/lancamentos/$id'),
      );
    }
    lastRemovedId = id;
  }

  @override
  Future<void> confirmar(
    String id, {
    double? valor,
    DateTime? dataVencimento,
    String? contaId,
    String? cartaoId,
  }) async {
    confirmarCallCount++;
    if (shouldFailConfirmar) {
      throw DioException(
        requestOptions: RequestOptions(
          path: '/financas/lancamentos/$id/confirmar',
        ),
      );
    }
    lastConfirmarArgs = {
      'id': id,
      'valor': valor,
      'dataVencimento': dataVencimento,
      'contaId': contaId,
      'cartaoId': cartaoId,
    };
  }
}

Widget _app(
  _FakeLancamentosRepository lancamentosRepo, {
  LancamentoFinanceiro? existente,
  ThemeData? theme,
  List<ContaFinanceira> contas = const [
    ContaFinanceira(
      id: 'conta-1',
      nome: 'Conta corrente',
      tipo: TipoContaFinanceira.corrente,
      saldoAtual: 1000,
    ),
  ],
}) {
  return ProviderScope(
    overrides: [
      contasRepositoryProvider.overrideWithValue(_FakeContasRepository(contas)),
      cartoesRepositoryProvider.overrideWithValue(_FakeCartoesRepository()),
      lancamentosRepositoryProvider.overrideWithValue(lancamentosRepo),
    ],
    child: MaterialApp(
      theme: theme ?? sincroLightTheme,
      home: NovoLancamentoScreen(existente: existente),
    ),
  );
}

/// Luminância relativa (WCAG 2.x) de uma cor — usada para calcular contraste texto/fundo do
/// banner pendente (item 1 do crítico). `Color.r/g/b` já vêm normalizados em 0.0–1.0.
double _luminanciaRelativa(Color cor) {
  double canal(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  final r = canal(cor.r);
  final g = canal(cor.g);
  final b = canal(cor.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Razão de contraste WCAG entre duas cores — o mínimo para AA em texto normal é 4,5:1.
double _contraste(Color a, Color b) {
  final la = _luminanciaRelativa(a) + 0.05;
  final lb = _luminanciaRelativa(b) + 0.05;
  return la > lb ? la / lb : lb / la;
}

/// A tela é um `ListView` (constrói filhos sob demanda): com o banner de contexto no topo, o
/// botão de salvar fica abaixo da dobra na viewport do teste e o finder não o encontra sem rolar.
Future<void> _tapBotao(WidgetTester tester, String rotulo) async {
  final finder = find.widgetWithText(ElevatedButton, rotulo);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Como `_tapBotao`, mas só dá um `pump()` em vez de `pumpAndSettle()` — usada quando o teste
/// precisa inspecionar um estado intermediário (ex.: o campo já reformatado) antes do
/// salvamento (assíncrono) terminar de vez.
Future<void> _tapBotaoSemAssentar(WidgetTester tester, String rotulo) async {
  final finder = find.widgetWithText(ElevatedButton, rotulo);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(finder);
  await tester.pump();
}

/// Como `_app`, mas a tela é EMPURRADA por cima de uma home — necessário para exercitar o
/// botão de voltar da AppBar (`Navigator.maybePop`) e o guard de descarte.
Widget _appComRota(
  _FakeLancamentosRepository lancamentosRepo, {
  LancamentoFinanceiro? existente,
}) {
  return ProviderScope(
    overrides: [
      contasRepositoryProvider.overrideWithValue(_FakeContasRepository()),
      cartoesRepositoryProvider.overrideWithValue(_FakeCartoesRepository()),
      lancamentosRepositoryProvider.overrideWithValue(lancamentosRepo),
    ],
    child: MaterialApp(
      theme: sincroLightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NovoLancamentoScreen(existente: existente),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

final _lancamentoExistente = LancamentoFinanceiro(
  id: 'l-existente',
  tipo: TipoLancamento.despesa,
  descricao: 'Aluguel',
  instituicao: null,
  valor: 1450.0,
  dataVencimento: DateTime.utc(2026, 9, 10),
  dataCompetencia: DateTime.utc(2026, 9, 10),
  status: StatusLancamento.confirmado,
  origem: OrigemLancamento.manual,
  isPago: false,
  codigoBarras: null,
  cartaoId: null,
  contaId: null,
);

final _lancamentoPendente = LancamentoFinanceiro(
  id: 'l-pendente',
  tipo: TipoLancamento.faturaCartao,
  descricao: 'Fatura Nubank',
  instituicao: 'Nubank',
  valor: 512.40,
  dataVencimento: DateTime.utc(2026, 10, 10),
  dataCompetencia: DateTime.utc(2026, 10, 10),
  status: StatusLancamento.pendenteRevisao,
  origem: OrigemLancamento.emailParser,
  isPago: false,
  codigoBarras: null,
  cartaoId: null,
  contaId: null,
);

void main() {
  testWidgets('defaults to Despesa and saves with the entered fields', (
    tester,
  ) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Descrição'),
      'Mercado',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Valor'), '150,00');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(repo.lastCreateArgs, isNotNull);
    expect(repo.lastCreateArgs!['tipo'], TipoLancamento.despesa);
    expect(repo.lastCreateArgs!['descricao'], 'Mercado');
    expect(repo.lastCreateArgs!['valor'], 150.0);
  });

  testWidgets('switching to Receita changes the saved tipo', (tester) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Receita'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Descrição'),
      'Freela',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(repo.lastCreateArgs!['tipo'], TipoLancamento.receita);
  });

  testWidgets(
    'shows a calm error and does not close the screen when create fails',
    (tester) async {
      final repo = _FakeLancamentosRepository()..shouldFail = true;
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Descrição'),
        'Mercado',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(find.byType(NovoLancamentoScreen), findsOneWidget);
      expect(find.textContaining('Não foi possível salvar'), findsOneWidget);
    },
  );

  testWidgets('does not save when descrição is empty', (tester) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(repo.lastCreateArgs, isNull);
  });

  testWidgets(
    'editing an existing lançamento pre-fills the fields and shows "Editar lançamento"',
    (tester) async {
      final repo = _FakeLancamentosRepository();
      await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
      await tester.pumpAndSettle();

      expect(find.text('Editar lançamento'), findsOneWidget);
      expect(find.text('Aluguel'), findsOneWidget);
      expect(find.text('1450,00'), findsOneWidget);
    },
  );

  testWidgets('saving an edit calls update(), not create()', (tester) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Descrição'),
      'Aluguel (novo valor)',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(repo.lastCreateArgs, isNull);
    expect(repo.lastUpdateArgs, isNotNull);
    expect(repo.lastUpdateArgs!['id'], 'l-existente');
    expect(repo.lastUpdateArgs!['descricao'], 'Aluguel (novo valor)');
  });

  testWidgets(
    'saving an edit without touching the valor field keeps the value unchanged',
    (tester) async {
      final repo = _FakeLancamentosRepository();
      await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
      await tester.pumpAndSettle();

      // Regressão: abrir para edição e salvar sem mexer em nada não pode inflar 1450,00 para 14500,00.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(repo.lastUpdateArgs!['valor'], 1450.0);
    },
  );

  testWidgets(
    'editing a lançamento with a decimal valor pre-fills it in comma format',
    (tester) async {
      final repo = _FakeLancamentosRepository();
      final comCentavos = LancamentoFinanceiro(
        id: 'l-centavos',
        tipo: TipoLancamento.despesa,
        descricao: 'Mercado',
        instituicao: null,
        valor: 512.4,
        dataVencimento: DateTime.utc(2026, 9, 10),
        dataCompetencia: DateTime.utc(2026, 9, 10),
        status: StatusLancamento.confirmado,
        origem: OrigemLancamento.manual,
        isPago: false,
        codigoBarras: null,
        cartaoId: null,
        contaId: null,
      );
      await tester.pumpWidget(_app(repo, existente: comCentavos));
      await tester.pumpAndSettle();

      expect(find.text('512,40'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(repo.lastUpdateArgs!['valor'], 512.4);
    },
  );

  testWidgets(
    'shows a delete button only when editing, and confirming it removes and pops',
    (tester) async {
      final repo = _FakeLancamentosRepository();
      await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Excluir'));
      await tester.pumpAndSettle();

      expect(repo.lastRemovedId, 'l-existente');
    },
  );

  testWidgets('does not show a delete button when creating a new lançamento', (
    tester,
  ) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets(
    'editing a lançamento PENDENTE_REVISAO shows "Revisar lançamento" and "Confirmar e salvar"',
    (tester) async {
      final repo = _FakeLancamentosRepository();
      await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
      await tester.pumpAndSettle();

      expect(find.text('Revisar lançamento'), findsOneWidget);
      expect(find.text('Editar lançamento'), findsNothing);
      await tester.scrollUntilVisible(
        find.widgetWithText(ElevatedButton, 'Confirmar e salvar'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.widgetWithText(ElevatedButton, 'Confirmar e salvar'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'saving a lançamento PENDENTE_REVISAO calls update() then confirmar(), and pops',
    (tester) async {
      final repo = _FakeLancamentosRepository();
      await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
      await tester.pumpAndSettle();

      await _tapBotao(tester, 'Confirmar e salvar');

      expect(repo.lastUpdateArgs, isNotNull);
      expect(repo.lastUpdateArgs!['id'], 'l-pendente');
      expect(repo.confirmarCallCount, 1);
      expect(repo.lastConfirmarArgs!['id'], 'l-pendente');
      expect(repo.lastConfirmarArgs!['valor'], 512.4);
      expect(find.byType(NovoLancamentoScreen), findsNothing);
    },
  );

  testWidgets(
    'when confirmar() fails after a successful update(), shows an error and keeps the screen open',
    (tester) async {
      final repo = _FakeLancamentosRepository()..shouldFailConfirmar = true;
      await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
      await tester.pumpAndSettle();

      await _tapBotao(tester, 'Confirmar e salvar');

      expect(repo.lastUpdateArgs, isNotNull);
      expect(repo.confirmarCallCount, 1);
      expect(find.byType(NovoLancamentoScreen), findsOneWidget);
      expect(
        find.textContaining('salvo, mas não foi possível confirmar'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'saving a lançamento that is already CONFIRMADO does not call confirmar()',
    (tester) async {
      final repo = _FakeLancamentosRepository();
      await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(repo.lastUpdateArgs, isNotNull);
      expect(repo.confirmarCallCount, 0);
    },
  );

  group('revisão de pendente — valor (itens 1 e 2 do crítico)', () {
    testWidgets(
      'campo vazio num pendente é erro visível, nada é salvo e a tela fica aberta',
      (tester) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextField, 'Valor'), '');
        await _tapBotao(tester, 'Confirmar e salvar');

        expect(find.text('Informe o valor do lançamento.'), findsOneWidget);
        expect(repo.lastUpdateArgs, isNull);
        expect(repo.confirmarCallCount, 0);
        expect(find.byType(NovoLancamentoScreen), findsOneWidget);
      },
    );

    testWidgets(
      'texto que não parseia ("1,2,3") é erro visível e nada é salvo',
      (tester) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Valor'),
          '1,2,3',
        );
        await _tapBotao(tester, 'Confirmar e salvar');

        expect(find.textContaining('Valor inválido'), findsOneWidget);
        expect(repo.lastUpdateArgs, isNull);
        expect(repo.confirmarCallCount, 0);
      },
    );

    testWidgets(
      'letras são filtradas na digitação: "abc" deixa o campo vazio (não confirma com o valor antigo)',
      (tester) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextField, 'Valor'), 'abc');
        await _tapBotao(tester, 'Confirmar e salvar');

        expect(find.text('Informe o valor do lançamento.'), findsOneWidget);
        expect(repo.confirmarCallCount, 0);
      },
    );

    testWidgets(
      'valor editado vai para update() E confirmar() — nunca o valor antigo',
      (tester) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Valor'),
          '600,10',
        );
        await _tapBotao(tester, 'Confirmar e salvar');

        expect(repo.lastUpdateArgs!['valor'], 600.1);
        expect(repo.lastConfirmarArgs!['valor'], 600.1);
        expect(find.byType(NovoLancamentoScreen), findsNothing);
      },
    );

    for (final caso in const [
      ('1234.56', 1234.56),
      ('1.234,56', 1234.56),
      ('1234,56', 1234.56),
      ('1.234', 1234.0),
      ('R\$ 1.234,56', 1234.56),
      ('12', 12.0),
    ]) {
      testWidgets('normalização de valor: "${caso.$1}" → ${caso.$2}', (
        tester,
      ) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Descrição'),
          'Teste',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Valor'),
          caso.$1,
        );
        await _tapBotao(tester, 'Salvar');

        expect(repo.lastCreateArgs!['valor'], caso.$2);
      });
    }
  });

  group(
    'revisão de pendente — tipo, contexto e descarte (itens 3 e 6 do crítico)',
    () {
      testWidgets(
        'fatura de cartão mostra o tipo como chip, sem seletor, e o update preserva o tipo',
        (tester) async {
          final repo = _FakeLancamentosRepository();
          await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
          await tester.pumpAndSettle();

          expect(find.byType(SegmentedButton<TipoLancamento>), findsNothing);
          expect(find.widgetWithText(Chip, 'Fatura de cartão'), findsOneWidget);

          await _tapBotao(tester, 'Confirmar e salvar');
          expect(repo.lastUpdateArgs!['tipo'], TipoLancamento.faturaCartao);
        },
      );

      testWidgets('despesa comum continua com o seletor Despesa/Receita', (
        tester,
      ) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
        await tester.pumpAndSettle();

        expect(find.byType(SegmentedButton<TipoLancamento>), findsOneWidget);
        expect(find.widgetWithText(Chip, 'Fatura de cartão'), findsNothing);
      });

      testWidgets('banner mostra de onde veio, valor e vencimento lidos', (
        tester,
      ) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
        await tester.pumpAndSettle();

        expect(find.text('Detectado no e-mail do Nubank'), findsOneWidget);
        expect(find.textContaining('Valor lido: R\$'), findsOneWidget);
        expect(find.textContaining('512,40'), findsWidgets);
        expect(find.text('Vencimento lido: 10/10/2026'), findsOneWidget);
      });

      testWidgets('banner sem instituição e sem valor não inventa nada', (
        tester,
      ) async {
        final repo = _FakeLancamentosRepository();
        final semDados = LancamentoFinanceiro(
          id: 'l-sem',
          tipo: TipoLancamento.despesa,
          descricao: 'Boleto',
          instituicao: null,
          valor: null,
          dataVencimento: DateTime.utc(2026, 10, 10),
          dataCompetencia: DateTime.utc(2026, 10, 10),
          status: StatusLancamento.pendenteRevisao,
          origem: OrigemLancamento.emailParser,
          isPago: false,
          codigoBarras: null,
          cartaoId: null,
          contaId: null,
        );
        await tester.pumpWidget(_app(repo, existente: semDados));
        await tester.pumpAndSettle();

        expect(find.text('Detectado de um e-mail'), findsOneWidget);
        expect(find.text('Valor lido: não identificado'), findsOneWidget);
      });

      testWidgets('editar um lançamento já confirmado não mostra o banner', (
        tester,
      ) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
        await tester.pumpAndSettle();

        expect(find.textContaining('Detectado'), findsNothing);
      });

      testWidgets('voltar sem alterações sai direto, sem perguntar', (
        tester,
      ) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(
          _appComRota(repo, existente: _lancamentoPendente),
        );
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        expect(find.byType(NovoLancamentoScreen), findsOneWidget);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(find.text('Descartar alterações?'), findsNothing);
        expect(find.byType(NovoLancamentoScreen), findsNothing);
        expect(repo.lastUpdateArgs, isNull);
        expect(repo.confirmarCallCount, 0);
      });

      testWidgets(
        'voltar com alterações pergunta; "Continuar editando" mantém, "Descartar" sai sem salvar',
        (tester) async {
          final repo = _FakeLancamentosRepository();
          await tester.pumpWidget(
            _appComRota(repo, existente: _lancamentoPendente),
          );
          await tester.tap(find.text('abrir'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Descrição'),
            'Fatura Nubank (editada)',
          );
          // O guard de descarte é lido do PopScope já construído: um frame entre digitar e
          // tocar voltar (que um usuário real sempre tem) é o que o atualiza.
          await tester.pump();
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();

          expect(find.text('Descartar alterações?'), findsOneWidget);
          await tester.tap(find.text('Continuar editando'));
          await tester.pumpAndSettle();
          expect(find.byType(NovoLancamentoScreen), findsOneWidget);
          expect(find.text('Fatura Nubank (editada)'), findsOneWidget);

          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Descartar'));
          await tester.pumpAndSettle();

          expect(find.byType(NovoLancamentoScreen), findsNothing);
          expect(repo.lastUpdateArgs, isNull);
          expect(repo.confirmarCallCount, 0);
        },
      );
    },
  );

  group('correções do crítico cego (itens 1 a 8)', () {
    for (final par in [
      (sincroLightTheme, 'light'),
      (sincroDarkTheme, 'dark'),
    ]) {
      testWidgets(
        'item 1: banner pendente mantém contraste WCAG AA (≥4,5:1) no tema ${par.$2}',
        (tester) async {
          final repo = _FakeLancamentosRepository();
          await tester.pumpWidget(
            _app(repo, existente: _lancamentoPendente, theme: par.$1),
          );
          await tester.pumpAndSettle();

          final card = tester.widget<Card>(find.byType(Card));
          final fundo = card.color;
          expect(fundo, isNotNull);

          final rotulo = tester.widget<Text>(
            find.textContaining('Detectado no e-mail'),
          );
          final corpo = tester.widget<Text>(find.textContaining('Valor lido'));
          final corDoRotulo = rotulo.style?.color;
          final corDoCorpo = corpo.style?.color;
          expect(
            corDoRotulo,
            isNotNull,
            reason:
                'o texto do rótulo precisa de uma cor explícita para ser testável',
          );
          expect(
            corDoCorpo,
            isNotNull,
            reason:
                'o texto do corpo precisa de uma cor explícita para ser testável',
          );

          expect(
            _contraste(fundo!, corDoRotulo!),
            greaterThanOrEqualTo(4.5),
            reason:
                'rótulo do banner sem contraste suficiente no tema ${par.$2}',
          );
          expect(
            _contraste(fundo, corDoCorpo!),
            greaterThanOrEqualTo(4.5),
            reason:
                'texto do banner sem contraste suficiente no tema ${par.$2}',
          );
        },
      );
    }

    testWidgets(
      'item 2: pop da rota antes da resposta não lança exceção e ainda invalida os providers',
      (tester) async {
        final repo = _FakeLancamentosRepository();
        final gate = Completer<void>();
        repo.gateDoUpdate = gate.future;

        final snapshots = <AsyncValue<List<LancamentoFinanceiro>>>[];

        await tester.pumpWidget(
          _appComRota(repo, existente: _lancamentoPendente),
        );
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(NovoLancamentoScreen)),
          listen: false,
        );
        final subscription = container
            .listen<AsyncValue<List<LancamentoFinanceiro>>>(
              lancamentosPendentesProvider,
              (previous, next) => snapshots.add(next),
              fireImmediately: true,
            );

        await tester.scrollUntilVisible(
          find.widgetWithText(ElevatedButton, 'Confirmar e salvar'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Confirmar e salvar'),
        );
        // Não usa pumpAndSettle: a chamada fica parada dentro de update(), esperando `gate`.
        await tester.pump();

        // Sem edições no formulário: o botão de voltar sai direto (canPop), desmontando a
        // tela com a requisição de salvamento ainda em voo — é o repro exato do crítico.
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(NovoLancamentoScreen), findsNothing);

        final totalDeSnapshotsAntes = snapshots.length;
        gate.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(snapshots.length, greaterThan(totalDeSnapshotsAntes));

        subscription.close();
      },
    );

    for (final caso in const [
      ('10.5', 10.5),
      ('1.2', 1.2),
      ('1.234.567', 1234567.0),
    ]) {
      testWidgets('item 3: normalização de valor: "${caso.$1}" → ${caso.$2}', (
        tester,
      ) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Descrição'),
          'Teste',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Valor'),
          caso.$1,
        );
        await _tapBotao(tester, 'Salvar');

        expect(repo.lastCreateArgs!['valor'], caso.$2);
      });
    }

    testWidgets(
      'item 4: despesa com conta selecionada envia a conta ao salvar (antes era descartada)',
      (tester) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo));
        await tester.pumpAndSettle();

        expect(find.byType(SegmentedButton<TipoLancamento>), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'Descrição'),
          'Compra parcelada',
        );
        await tester.tap(find.byType(DropdownButtonFormField<String?>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Conta corrente').last);
        await tester.pumpAndSettle();

        await _tapBotao(tester, 'Salvar');

        expect(repo.lastCreateArgs!['tipo'], TipoLancamento.despesa);
        expect(repo.lastCreateArgs!['contaId'], 'conta-1');
      },
    );

    testWidgets(
      'item 5: valor "0" ao confirmar um pendente é erro "Informe um valor maior que zero."',
      (tester) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextField, 'Valor'), '0');
        await _tapBotao(tester, 'Confirmar e salvar');

        expect(find.text('Informe um valor maior que zero.'), findsOneWidget);
        expect(repo.lastUpdateArgs, isNull);
        expect(repo.confirmarCallCount, 0);
        expect(find.byType(NovoLancamentoScreen), findsOneWidget);
      },
    );

    testWidgets(
      'item 5: valor "1,234" é arredondado para 1,23 (2 casas decimais) e mostrado assim no campo',
      (tester) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Valor'),
          '1,234',
        );
        await _tapBotaoSemAssentar(tester, 'Confirmar e salvar');

        expect(find.text('1,23'), findsOneWidget);

        await tester.pumpAndSettle();
        expect(repo.lastUpdateArgs!['valor'], 1.23);
        expect(repo.lastConfirmarArgs!['valor'], 1.23);
      },
    );

    testWidgets(
      'item 6: escolher o mesmo dia no date picker não marca "alterações" (volta sem perguntar)',
      (tester) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(
          _appComRota(repo, existente: _lancamentoPendente),
        );
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ListTile, 'Vencimento'));
        await tester.pumpAndSettle();
        // Confirma a mesma data (10/10/2026) já selecionada, sem navegar o calendário.
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(find.text('Descartar alterações?'), findsNothing);
        expect(find.byType(NovoLancamentoScreen), findsNothing);
        expect(repo.lastUpdateArgs, isNull);
      },
    );

    testWidgets(
      'item 7: apagar o valor de um lançamento CONFIRMADO e salvar mostra erro e não fecha a tela',
      (tester) async {
        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextField, 'Valor'), '');
        await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
        await tester.pumpAndSettle();

        expect(find.text('Informe o valor do lançamento.'), findsOneWidget);
        expect(repo.lastUpdateArgs, isNull);
        expect(find.byType(NovoLancamentoScreen), findsOneWidget);
      },
    );

    testWidgets(
      'item 8: em telas largas (1440x900) o conteúdo (banner incluso) fica limitado a 600 de largura',
      (tester) async {
        addTearDown(tester.view.reset);
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;

        final repo = _FakeLancamentosRepository();
        await tester.pumpWidget(_app(repo, existente: _lancamentoPendente));
        await tester.pumpAndSettle();

        final tamanho = tester.getSize(find.byType(Card));
        expect(tamanho.width, lessThanOrEqualTo(600));
      },
    );
  });
}

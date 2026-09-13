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
  _FakeContasRepository() : super(Dio());
  @override
  Future<List<ContaFinanceira>> list() async => const [
        ContaFinanceira(id: 'conta-1', nome: 'Conta corrente', tipo: TipoContaFinanceira.corrente, saldoAtual: 1000),
      ];
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
  String? lastRemovedId;
  bool shouldFail = false;

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
    if (shouldFail) throw DioException(requestOptions: RequestOptions(path: '/financas/lancamentos'));
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
    if (shouldFail) throw DioException(requestOptions: RequestOptions(path: '/financas/lancamentos/$id'));
    lastUpdateArgs = {'id': id, 'descricao': descricao, 'valor': valor, 'isPago': isPago};
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
    if (shouldFail) throw DioException(requestOptions: RequestOptions(path: '/financas/lancamentos/$id'));
    lastRemovedId = id;
  }
}

Widget _app(_FakeLancamentosRepository lancamentosRepo, {LancamentoFinanceiro? existente}) {
  return ProviderScope(
    overrides: [
      contasRepositoryProvider.overrideWithValue(_FakeContasRepository()),
      cartoesRepositoryProvider.overrideWithValue(_FakeCartoesRepository()),
      lancamentosRepositoryProvider.overrideWithValue(lancamentosRepo),
    ],
    child: MaterialApp(
      theme: sincroLightTheme,
      home: NovoLancamentoScreen(existente: existente),
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

void main() {
  testWidgets('defaults to Despesa and saves with the entered fields', (tester) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Descrição'), 'Mercado');
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
    await tester.enterText(find.widgetWithText(TextField, 'Descrição'), 'Freela');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(repo.lastCreateArgs!['tipo'], TipoLancamento.receita);
  });

  testWidgets('shows a calm error and does not close the screen when create fails', (tester) async {
    final repo = _FakeLancamentosRepository()..shouldFail = true;
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Descrição'), 'Mercado');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.byType(NovoLancamentoScreen), findsOneWidget);
    expect(find.textContaining('Não foi possível salvar'), findsOneWidget);
  });

  testWidgets('does not save when descrição is empty', (tester) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(repo.lastCreateArgs, isNull);
  });

  testWidgets('editing an existing lançamento pre-fills the fields and shows "Editar lançamento"', (tester) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
    await tester.pumpAndSettle();

    expect(find.text('Editar lançamento'), findsOneWidget);
    expect(find.text('Aluguel'), findsOneWidget);
    expect(find.text('1450,00'), findsOneWidget);
  });

  testWidgets('saving an edit calls update(), not create()', (tester) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Descrição'), 'Aluguel (novo valor)');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(repo.lastCreateArgs, isNull);
    expect(repo.lastUpdateArgs, isNotNull);
    expect(repo.lastUpdateArgs!['id'], 'l-existente');
    expect(repo.lastUpdateArgs!['descricao'], 'Aluguel (novo valor)');
  });

  testWidgets('saving an edit without touching the valor field keeps the value unchanged', (
    tester,
  ) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
    await tester.pumpAndSettle();

    // Regressão: abrir para edição e salvar sem mexer em nada não pode inflar 1450,00 para 14500,00.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(repo.lastUpdateArgs!['valor'], 1450.0);
  });

  testWidgets('editing a lançamento with a decimal valor pre-fills it in comma format', (
    tester,
  ) async {
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
  });

  testWidgets('shows a delete button only when editing, and confirming it removes and pops', (tester) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo, existente: _lancamentoExistente));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Excluir'));
    await tester.pumpAndSettle();

    expect(repo.lastRemovedId, 'l-existente');
  });

  testWidgets('does not show a delete button when creating a new lançamento', (tester) async {
    final repo = _FakeLancamentosRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}

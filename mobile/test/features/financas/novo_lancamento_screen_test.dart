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
}

Widget _app(_FakeLancamentosRepository lancamentosRepo) {
  return ProviderScope(
    overrides: [
      contasRepositoryProvider.overrideWithValue(_FakeContasRepository()),
      cartoesRepositoryProvider.overrideWithValue(_FakeCartoesRepository()),
      lancamentosRepositoryProvider.overrideWithValue(lancamentosRepo),
    ],
    child: MaterialApp(theme: sincroLightTheme, home: const NovoLancamentoScreen()),
  );
}

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
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
}

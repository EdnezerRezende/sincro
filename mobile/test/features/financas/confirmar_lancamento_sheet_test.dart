import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/financas/confirmar_lancamento_sheet.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';
import 'package:sincro_mobile/features/financas/lancamentos_repository.dart';

class _FakeLancamentosRepository extends LancamentosRepository {
  _FakeLancamentosRepository() : super(Dio());
  String? confirmedId;
  String? ignoredId;

  @override
  Future<void> confirmar(
    String id, {
    double? valor,
    DateTime? dataVencimento,
    String? contaId,
    String? cartaoId,
  }) async {
    confirmedId = id;
  }

  @override
  Future<void> ignorar(String id) async {
    ignoredId = id;
  }
}

final _lancamento = LancamentoFinanceiro(
  id: 'l1',
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
  testWidgets(
    'Confirmar button calls repository.confirmar with the lançamento id',
    (tester) async {
      final repository = _FakeLancamentosRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (sheetContext) => ConfirmarLancamentoSheetContent(
                    lancamento: _lancamento,
                    onConfirmar: () => repository.confirmar(_lancamento.id),
                    onIgnorar: () => repository.ignorar(_lancamento.id),
                  ),
                ),
                child: const Text('abrir'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Fatura Nubank'), findsOneWidget);
      expect(find.textContaining('512,40'), findsOneWidget);

      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(repository.confirmedId, 'l1');
    },
  );

  testWidgets(
    'Ignorar button calls repository.ignorar with the lançamento id',
    (tester) async {
      final repository = _FakeLancamentosRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (sheetContext) => ConfirmarLancamentoSheetContent(
                    lancamento: _lancamento,
                    onConfirmar: () => repository.confirmar(_lancamento.id),
                    onIgnorar: () => repository.ignorar(_lancamento.id),
                  ),
                ),
                child: const Text('abrir'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ignorar'));
      await tester.pumpAndSettle();

      expect(repository.ignoredId, 'l1');
    },
  );
}

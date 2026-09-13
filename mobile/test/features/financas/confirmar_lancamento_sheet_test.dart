import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/financas/confirmar_lancamento_sheet.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';
import 'package:sincro_mobile/features/financas/lancamentos_repository.dart';

class _FakeLancamentosRepository extends LancamentosRepository {
  _FakeLancamentosRepository({
    this.throwOnConfirmar = false,
    this.throwOnIgnorar = false,
    this.delay,
  }) : super(Dio());
  String? confirmedId;
  String? ignoredId;
  int confirmarCallCount = 0;
  final bool throwOnConfirmar;
  final bool throwOnIgnorar;
  final Duration? delay;

  @override
  Future<void> confirmar(
    String id, {
    double? valor,
    DateTime? dataVencimento,
    String? contaId,
    String? cartaoId,
  }) async {
    confirmarCallCount++;
    if (delay != null) await Future<void>.delayed(delay!);
    if (throwOnConfirmar) {
      throw DioException(requestOptions: RequestOptions(path: '/financas/lancamentos/$id/confirmar'));
    }
    confirmedId = id;
  }

  @override
  Future<void> ignorar(String id) async {
    if (delay != null) await Future<void>.delayed(delay!);
    if (throwOnIgnorar) {
      throw DioException(requestOptions: RequestOptions(path: '/financas/lancamentos/$id/ignorar'));
    }
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

  Widget _appFor(_FakeLancamentosRepository repository) {
    return ProviderScope(
      overrides: [
        lancamentosRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: sincroLightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    onPressed: () => showConfirmarLancamentoSheet(
                      context,
                      ref,
                      _lancamento,
                    ),
                    child: const Text('abrir'),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  testWidgets(
    'showConfirmarLancamentoSheet: on success calls the repository and closes the sheet',
    (tester) async {
      final repository = _FakeLancamentosRepository();
      await tester.pumpWidget(_appFor(repository));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar lançamento'), findsOneWidget);

      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(repository.confirmedId, 'l1');
      expect(find.text('Confirmar lançamento'), findsNothing);
    },
  );

  testWidgets(
    'showConfirmarLancamentoSheet: on repository failure, keeps the sheet open and shows a SnackBar',
    (tester) async {
      final repository = _FakeLancamentosRepository(throwOnConfirmar: true);
      await tester.pumpWidget(_appFor(repository));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmar lançamento'), findsOneWidget);
      expect(
        find.text('Não foi possível confirmar agora. Tente novamente.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'showConfirmarLancamentoSheet: Ignorar failure keeps the sheet open and shows a SnackBar',
    (tester) async {
      final repository = _FakeLancamentosRepository(throwOnIgnorar: true);
      await tester.pumpWidget(_appFor(repository));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ignorar'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmar lançamento'), findsOneWidget);
      expect(
        find.text('Não foi possível ignorar agora. Tente novamente.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'showConfirmarLancamentoSheet: disables the buttons while the request is in flight '
    'and ignores a second tap (double-tap guard)',
    (tester) async {
      final repository = _FakeLancamentosRepository(
        delay: const Duration(milliseconds: 200),
      );
      await tester.pumpWidget(_appFor(repository));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirmar'));
      await tester.pump(); // apenas o rebuild que desabilita os botões, sem resolver o Future.

      // Enquanto a requisição está em voo, o FilledButton mostra um spinner em vez do texto,
      // e um segundo toque não deve gerar uma segunda chamada ao repositório.
      expect(find.text('Confirmar'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      final filledButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(filledButton.onPressed, isNull);
      final outlinedButton = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(outlinedButton.onPressed, isNull);

      await tester.pumpAndSettle();

      expect(repository.confirmarCallCount, 1);
      expect(find.text('Confirmar lançamento'), findsNothing);
    },
  );
}

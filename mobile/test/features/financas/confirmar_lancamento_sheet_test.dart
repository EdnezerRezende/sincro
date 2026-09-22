import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/financas/confirmar_lancamento_sheet.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';
import 'package:sincro_mobile/features/financas/lancamentos_repository.dart';
import 'package:sincro_mobile/features/financas/novo_lancamento_screen.dart';

class _FakeLancamentosRepository extends LancamentosRepository {
  _FakeLancamentosRepository({this.throwOnIgnorar = false, this.delay})
    : super(Dio());
  String? confirmedId;
  String? ignoredId;
  int confirmarCallCount = 0;
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
    confirmedId = id;
  }

  @override
  Future<void> ignorar(String id) async {
    if (delay != null) await Future<void>.delayed(delay!);
    if (throwOnIgnorar) {
      throw DioException(
        requestOptions: RequestOptions(
          path: '/financas/lancamentos/$id/ignorar',
        ),
      );
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
    'Confirmar button navigates to NovoLancamentoScreen without calling repository.confirmar',
    (tester) async {
      final repository = _FakeLancamentosRepository();
      var pushed = false;

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
                    onConfirmar: () {
                      pushed = true;
                      Navigator.of(sheetContext).pop();
                    },
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

      await tester.tap(find.text('Revisar e confirmar'));
      await tester.pumpAndSettle();

      expect(pushed, isTrue);
      expect(repository.confirmarCallCount, 0);
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
                    onConfirmar: () => Navigator.of(sheetContext).pop(),
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

  Widget appFor(_FakeLancamentosRepository repository) {
    return ProviderScope(
      overrides: [lancamentosRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: sincroLightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    onPressed: () =>
                        showConfirmarLancamentoSheet(context, ref, _lancamento),
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
    'showConfirmarLancamentoSheet: Confirmar closes the sheet and opens NovoLancamentoScreen '
    'pré-preenchida, sem chamar a API',
    (tester) async {
      final repository = _FakeLancamentosRepository();
      await tester.pumpWidget(appFor(repository));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Lançamento detectado'), findsOneWidget);

      await tester.tap(find.text('Revisar e confirmar'));
      await tester.pumpAndSettle();

      // A sheet fechou e a confirmação real (chamada à API) ainda não aconteceu — ela só
      // ocorre quando o usuário salvar na tela de edição (ver novo_lancamento_screen_test.dart).
      expect(repository.confirmarCallCount, 0);
      expect(find.text('Lançamento detectado'), findsNothing);
      expect(find.byType(NovoLancamentoScreen), findsOneWidget);
      expect(find.text('Revisar lançamento'), findsOneWidget);
      expect(find.text('Fatura Nubank'), findsOneWidget);
    },
  );

  testWidgets(
    'showConfirmarLancamentoSheet: title and body reflect that nothing is saved yet '
    '(item 4), and the resumo fields are still shown',
    (tester) async {
      final repository = _FakeLancamentosRepository();
      await tester.pumpWidget(appFor(repository));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Lançamento detectado'), findsOneWidget);
      expect(
        find.textContaining('Nada é gravado até você revisar e salvar'),
        findsOneWidget,
      );
      expect(find.text('Descrição'), findsOneWidget);
      expect(find.text('Fatura Nubank'), findsOneWidget);
      expect(find.text('Valor'), findsOneWidget);
      expect(find.textContaining('512,40'), findsOneWidget);
      expect(find.text('Vencimento'), findsOneWidget);
      expect(find.text('Ignorar'), findsOneWidget);
      expect(find.text('Revisar e confirmar'), findsOneWidget);
    },
  );

  testWidgets(
    'showConfirmarLancamentoSheet: Ignorar failure keeps the sheet open and shows a SnackBar',
    (tester) async {
      final repository = _FakeLancamentosRepository(throwOnIgnorar: true);
      await tester.pumpWidget(appFor(repository));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ignorar'));
      await tester.pumpAndSettle();

      expect(find.text('Lançamento detectado'), findsOneWidget);
      expect(
        find.text('Não foi possível ignorar agora. Tente novamente.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'showConfirmarLancamentoSheet: shows the spinner on Ignorar (who is actually in flight) '
    'and disables Confirmar, while ignoring a second tap (double-tap guard)',
    (tester) async {
      final repository = _FakeLancamentosRepository(
        delay: const Duration(milliseconds: 200),
      );
      await tester.pumpWidget(appFor(repository));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ignorar'));
      await tester
          .pump(); // apenas o rebuild que desabilita os botões, sem resolver o Future.

      // `isSubmitting` é compartilhado pelos dois botões, mas só o Ignorar de fato fala com a
      // API aqui — é nele que o spinner deve aparecer. O FilledButton ("Revisar e confirmar")
      // mantém seu texto, só fica desabilitado.
      expect(find.text('Ignorar'), findsNothing);
      expect(find.text('Revisar e confirmar'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      final filledButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(filledButton.onPressed, isNull);
      final outlinedButton = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(outlinedButton.onPressed, isNull);

      await tester.pumpAndSettle();

      expect(repository.ignoredId, 'l1');
      expect(find.text('Lançamento detectado'), findsNothing);
    },
  );
}

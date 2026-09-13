import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'finance_providers.dart';
import 'lancamento_financeiro.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _dateFormat = DateFormat('dd/MM/yyyy');

Future<void> showConfirmarLancamentoSheet(
  BuildContext context,
  WidgetRef ref,
  LancamentoFinanceiro lancamento,
) {
  final repository = ref.read(lancamentosRepositoryProvider);

  void invalidateAfterMudanca() {
    // Confirmar/ignorar muda o que `GET /financas/resumo` retorna (Saldo Livre,
    // despesas pendentes) e, no caso de confirmar, move o item para o mês —
    // por isso invalidamos as duas outras fontes de dados da tela de Finanças
    // além da lista de pendentes. `lancamentosDoMesProvider` é `.family`;
    // invalidar sem argumento invalida todas as instâncias, o que está correto
    // aqui porque não sabemos qual mês a tela tem aberto no momento.
    ref.invalidate(lancamentosPendentesProvider);
    ref.invalidate(financeSummaryProvider);
    ref.invalidate(lancamentosDoMesProvider);
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      // `isSubmitting` precisa viver FORA do builder do StatefulBuilder: esse builder
      // interno é re-invocado a cada setState, então uma variável declarada dentro dele
      // seria reinicializada para `false` em todo rebuild, e o guard contra duplo toque
      // nunca teria efeito de verdade. Este builder externo (o do showModalBottomSheet) só
      // roda uma vez para a vida da sheet, então a variável aqui persiste entre os
      // rebuilds do StatefulBuilder interno.
      var isSubmitting = false;

      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> confirmar() async {
            setState(() => isSubmitting = true);
            try {
              await repository.confirmar(lancamento.id, valor: lancamento.valor);
              invalidateAfterMudanca();
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            } catch (_) {
              if (sheetContext.mounted) {
                setState(() => isSubmitting = false);
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Não foi possível confirmar agora. Tente novamente.',
                    ),
                  ),
                );
              }
            }
          }

          Future<void> ignorar() async {
            setState(() => isSubmitting = true);
            try {
              await repository.ignorar(lancamento.id);
              invalidateAfterMudanca();
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            } catch (_) {
              if (sheetContext.mounted) {
                setState(() => isSubmitting = false);
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Não foi possível ignorar agora. Tente novamente.',
                    ),
                  ),
                );
              }
            }
          }

          return ConfirmarLancamentoSheetContent(
            lancamento: lancamento,
            isSubmitting: isSubmitting,
            onConfirmar: confirmar,
            onIgnorar: ignorar,
          );
        },
      );
    },
  );
}

class ConfirmarLancamentoSheetContent extends StatelessWidget {
  const ConfirmarLancamentoSheetContent({
    super.key,
    required this.lancamento,
    required this.onConfirmar,
    required this.onIgnorar,
    this.isSubmitting = false,
  });

  final LancamentoFinanceiro lancamento;
  final VoidCallback onConfirmar;
  final VoidCallback onIgnorar;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final valor = lancamento.valor;
    final instituicao = lancamento.instituicao;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirmar lançamento',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            instituicao != null
                ? 'Detectamos isso a partir de um e-mail do $instituicao. Dá uma conferida antes de confirmar — sem pressa.'
                : 'Detectamos isso a partir de um e-mail. Dá uma conferida antes de confirmar — sem pressa.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Descrição', style: Theme.of(context).textTheme.labelSmall),
                    Text(
                      lancamento.descricao,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Valor', style: Theme.of(context).textTheme.labelSmall),
                    Text(
                      valor == null ? 'não informado' : _currency.format(valor),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Vencimento', style: Theme.of(context).textTheme.labelSmall),
          Text(
            _dateFormat.format(lancamento.dataVencimento),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isSubmitting ? null : onIgnorar,
                  child: const Text('Ignorar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: isSubmitting ? null : onConfirmar,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirmar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

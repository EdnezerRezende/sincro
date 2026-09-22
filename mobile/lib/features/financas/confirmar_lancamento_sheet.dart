import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'finance_providers.dart';
import 'lancamento_financeiro.dart';
import 'novo_lancamento_screen.dart';
import '../calendar/calendar_providers.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _dateFormat = DateFormat('dd/MM/yyyy');

Future<void> showConfirmarLancamentoSheet(
  BuildContext context,
  WidgetRef ref,
  LancamentoFinanceiro lancamento,
) {
  final repository = ref.read(lancamentosRepositoryProvider);

  void invalidateAfterMudanca() {
    // Ignorar muda o que `GET /financas/resumo` retorna (Saldo Livre, despesas
    // pendentes) e remove o item da lista de pendentes — por isso invalidamos
    // as demais fontes de dados da tela de Finanças além da lista de pendentes.
    // `lancamentosDoMesProvider` é `.family`; invalidar sem argumento invalida
    // todas as instâncias, o que está correto aqui porque não sabemos qual mês
    // a tela tem aberto no momento.
    // Confirmar não chama esta função: ele não fala mais com a API por aqui —
    // apenas abre a tela de edição, que é quem confirma (e invalida) ao salvar.
    ref.invalidate(lancamentosPendentesProvider);
    ref.invalidate(financeSummaryProvider);
    ref.invalidate(lancamentosDoMesProvider);
    // Ignorar remove o eventual evento já existente na Agenda. Mesmo raciocínio
    // de invalidação cruzada.
    ref.invalidate(upcomingEventsProvider);
    ref.invalidate(monthEventsProvider);
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
          // Confirmar NÃO fala com a API aqui: apenas fecha a sheet e leva o usuário para a
          // tela de edição pré-preenchida, onde ele pode revisar os valores detectados pelo
          // parser de e-mail antes de qualquer coisa ser gravada. A confirmação de verdade
          // (status PENDENTE_REVISAO -> CONFIRMADO) só acontece quando ele salva por lá — ver
          // `_salvar` em `NovoLancamentoScreen`. Isso evita marcar como confirmado algo que o
          // usuário ainda não revisou, ou que ele decida cancelar no meio do caminho.
          void confirmar() {
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            if (context.mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NovoLancamentoScreen(existente: lancamento),
                ),
              );
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
            'Lançamento detectado',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            instituicao != null
                ? 'Encontramos isso no e-mail do $instituicao. Nada é gravado até você revisar e salvar.'
                : 'Encontramos isso em um e-mail. Nada é gravado até você revisar e salvar.',
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
                    Text(
                      'Descrição',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
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
                    Text(
                      'Valor',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
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
                // O spinner fica no botão que de fato disparou a ação em voo (Ignorar é o
                // único que fala com a API aqui — Confirmar apenas navega). Antes, `isSubmitting`
                // trocava o texto do FilledButton ("Revisar e confirmar") pelo spinner mesmo
                // quando quem estava em voo era o Ignorar, dando a entender que a ação errada
                // estava em andamento.
                child: OutlinedButton(
                  onPressed: isSubmitting ? null : onIgnorar,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Ignorar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: isSubmitting ? null : onConfirmar,
                  child: const Text('Revisar e confirmar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

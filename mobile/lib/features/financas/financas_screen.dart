import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_chip.dart';
import '../calendar/calendar_providers.dart';
import 'confirmar_lancamento_sheet.dart';
import 'finance_providers.dart';
import 'finance_summary.dart';
import 'lancamento_financeiro.dart';
import 'novo_lancamento_screen.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _dateFormat = DateFormat('dd/MM');

/// Cor semântica do tipo de lançamento. Receita usa `sincroColors.success` (verde,
/// "entrando dinheiro"); despesa e fatura de cartão usam `colorScheme.error` (vermelho
/// dessaturado do design system). Ambas as cores são as mesmas usadas em todo o app —
/// nunca hardcoded — e têm contraste AA (>=4.5:1) contra `colorScheme.surface` em claro
/// e escuro (verificado: erro 5.62:1/4.76:1, sucesso 5.13:1/7.02:1).
Color _corTipo(BuildContext context, TipoLancamento tipo) {
  return tipo == TipoLancamento.receita
      ? context.sincroColors.success
      : Theme.of(context).colorScheme.error;
}

class FinancasScreen extends ConsumerStatefulWidget {
  const FinancasScreen({super.key});

  @override
  ConsumerState<FinancasScreen> createState() => _FinancasScreenState();
}

enum _Aba { pendentes, mes }

enum _TipoFiltro { todas, entradas, despesas }

enum _Ordenacao { tipo, data, valor }

extension on _Ordenacao {
  // Labels visuais SEM o prefixo "Ordenar:" — medido com um teste de layout real (não só
  // "parece caber"): mesmo só com "Ordenar: Data ↑" o texto ainda estourava a largura
  // disponível do dropdown em 320/360/390 dp (RenderParagraph.didExceedMaxLines == true),
  // porque o dropdown divide a linha com o texto "Filtrar por tipo" ao lado. O contexto
  // "Ordenar por" agora vem de uma legenda própria ao lado do dropdown (ver `build`),
  // então o valor selecionado só precisa do critério em si.
  // "Data ↑"/"Valor ↓" evitam afirmar uma semântica que a ordenação não cumpre: por
  // vencimento crescente, itens já VENCIDOS aparecem antes do próximo a vencer — não é
  // "mais próxima primeiro", é mais antiga primeiro cronologicamente. A seta indica
  // apenas a direção (crescente/decrescente), sem alegar isso.
  String get label {
    switch (this) {
      case _Ordenacao.tipo:
        return 'Tipo';
      case _Ordenacao.data:
        return 'Data ↑';
      case _Ordenacao.valor:
        return 'Valor ↓';
    }
  }

  // Rótulo completo só para leitores de tela (via `Semantics.label` no dropdown) — o
  // texto visível é curto para caber na tela, mas quem usa leitor de tela ainda ouve o
  // critério por extenso e a direção real da ordenação.
  String get semanticLabel {
    switch (this) {
      case _Ordenacao.tipo:
        return 'Ordenar por tipo, receitas primeiro';
      case _Ordenacao.data:
        return 'Ordenar por data de vencimento, mais antiga primeiro';
      case _Ordenacao.valor:
        return 'Ordenar por valor, maior primeiro';
    }
  }
}

class _FinancasScreenState extends ConsumerState<FinancasScreen> {
  _Aba _aba = _Aba.mes;
  _TipoFiltro _tipoFiltro = _TipoFiltro.todas;
  // Padrão "Data": ao lado do filtro "Tipo" (entradas/despesas), ordenar por "Tipo"
  // também é ambíguo — "Data" é mais útil e previsível como ponto de partida.
  _Ordenacao _ordenacao = _Ordenacao.data;

  List<LancamentoFinanceiro> _filtrarEOrdenar(
    List<LancamentoFinanceiro> lancamentos,
  ) {
    final filtrados = lancamentos.where((l) {
      switch (_tipoFiltro) {
        case _TipoFiltro.todas:
          return true;
        case _TipoFiltro.entradas:
          return l.tipo == TipoLancamento.receita;
        case _TipoFiltro.despesas:
          // Switch exaustivo: se um novo TipoLancamento for adicionado no futuro, o
          // analyzer aponta aqui em vez de silenciosamente cair no "é despesa".
          switch (l.tipo) {
            case TipoLancamento.despesa:
            case TipoLancamento.faturaCartao:
              return true;
            case TipoLancamento.receita:
              return false;
          }
      }
    }).toList();

    // Comparators totalmente determinísticos: `List.sort` não é estável no Dart, então
    // cada critério precisa de desempate até chegar em `id` (único), senão a ordem de
    // itens "empatados" no critério principal fica imprevisível entre execuções.
    int porData(LancamentoFinanceiro a, LancamentoFinanceiro b) =>
        a.dataVencimento.compareTo(b.dataVencimento);
    int porId(LancamentoFinanceiro a, LancamentoFinanceiro b) =>
        a.id.compareTo(b.id);

    // Chave semântica de agrupamento por tipo — NÃO usa `tipo.index` diretamente, pois
    // `TipoLancamento` é `[despesa, receita, faturaCartao]` e isso separaria
    // `faturaCartao` das despesas (ficaria depois de `receita`), inconsistente com o
    // agrupamento binário já usado no filtro "Despesas" (que inclui despesa+faturaCartao).
    // Switch exaustivo: um novo `TipoLancamento` futuro força decidir o grupo aqui.
    int chaveGrupoTipo(TipoLancamento tipo) {
      switch (tipo) {
        case TipoLancamento.receita:
          return 0;
        case TipoLancamento.despesa:
        case TipoLancamento.faturaCartao:
          return 1;
      }
    }

    filtrados.sort((a, b) {
      switch (_ordenacao) {
        case _Ordenacao.tipo:
          final tipo = chaveGrupoTipo(a.tipo).compareTo(chaveGrupoTipo(b.tipo));
          if (tipo != 0) return tipo;
          final data = porData(a, b);
          if (data != 0) return data;
          return porId(a, b);
        case _Ordenacao.data:
          final data = porData(a, b);
          if (data != 0) return data;
          return porId(a, b);
        case _Ordenacao.valor:
          final valor = (b.valor ?? 0).compareTo(a.valor ?? 0);
          if (valor != 0) return valor;
          return porId(a, b);
      }
    });

    return filtrados;
  }

  Widget _buildLista(
    List<LancamentoFinanceiro> itens,
    Widget Function(LancamentoFinanceiro) cardBuilder,
  ) {
    if (itens.isEmpty) {
      return _EmptyState(
        temFiltroAtivo: _tipoFiltro != _TipoFiltro.todas,
        onLimparFiltro: _tipoFiltro == _TipoFiltro.todas
            ? null
            : () => setState(() => _tipoFiltro = _TipoFiltro.todas),
      );
    }
    return Column(
      children: [
        for (final item in itens)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: cardBuilder(item),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(financeSummaryProvider);
    final pendentesAsync = ref.watch(lancamentosPendentesProvider);
    final mesAtual = DateFormat('yyyy-MM').format(DateTime.now());
    // Contador sempre do total de pendências (não filtrado pelo filtro de tipo abaixo) —
    // é o número que importa para saber quanto falta revisar, independente do que está
    // sendo exibido na lista no momento.
    final pendentesCount = pendentesAsync.maybeWhen(data: (p) => p.length, orElse: () => 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finanças'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Novo lançamento',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NovoLancamentoScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          summaryAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Não foi possível carregar seu resumo agora.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            data: (summary) => _SaldoLivreCard(summary: summary),
          ),
          const SizedBox(height: 20),
          AppChipGroup(
            chips: [
              AppChip(
                label: 'Lançamentos do mês',
                selected: _aba == _Aba.mes,
                variant: AppChipVariant.filter,
                onSelected: (_) => setState(() => _aba = _Aba.mes),
              ),
              AppChip(
                label: 'Pendentes de revisão ($pendentesCount)',
                selected: _aba == _Aba.pendentes,
                variant: AppChipVariant.filter,
                onSelected: (_) => setState(() => _aba = _Aba.pendentes),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // "Filtrar por tipo" e o dropdown de ordenação ficam em LINHAS separadas (não
          // mais dividindo a mesma Row) por dois motivos:
          // 1) Semântica: cada legenda + controle vira seu próprio bloco navegável, sem
          //    depender só de `Semantics(container: true)` lado a lado para não fundir os
          //    dois num único nó (um leitor de tela chegou a anunciar o dropdown de
          //    ORDENAÇÃO como se fosse o filtro de TIPO quando dividiam a linha).
          // 2) Espaço: com as duas legendas competindo pela mesma linha, o texto ativo do
          //    dropdown truncava em telas de 390 dp mesmo já encurtado — confirmado com
          //    `RenderParagraph.didExceedMaxLines`. Em linha própria, "Ordenar por" (curto)
          //    e o valor selecionado ("Data ↑"/"Valor ↓"/"Tipo") sempre cabem.
          Semantics(
            container: true,
            child: Text(
              'Filtrar por tipo',
              style: Theme.of(context).textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          AppChipGroup(
            chips: [
              AppChip(
                label: 'Todas',
                selected: _tipoFiltro == _TipoFiltro.todas,
                variant: AppChipVariant.filter,
                onSelected: (_) =>
                    setState(() => _tipoFiltro = _TipoFiltro.todas),
              ),
              AppChip(
                label: 'Entradas',
                selected: _tipoFiltro == _TipoFiltro.entradas,
                variant: AppChipVariant.filter,
                onSelected: (_) =>
                    setState(() => _tipoFiltro = _TipoFiltro.entradas),
              ),
              AppChip(
                label: 'Despesas',
                selected: _tipoFiltro == _TipoFiltro.despesas,
                variant: AppChipVariant.filter,
                onSelected: (_) =>
                    setState(() => _tipoFiltro = _TipoFiltro.despesas),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Bloco de ordenação isolado do bloco de filtro por tipo acima (própria linha,
          // próprio nó de semântica) — ver comentário no bloco "Filtrar por tipo".
          Semantics(
            container: true,
            child: Row(
              children: [
                // "Ordenar" (não "Ordenar por") + `bodySmall` (menor que o `titleSmall`
                // usado em "Filtrar por tipo"): medido com teste de layout real em 320 dp
                // — a legenda mais longa competia por espaço com o valor selecionado do
                // dropdown ao ponto de truncar "Data ↑"/"Valor ↓" mesmo já encurtados.
                Text(
                  'Ordenar',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    // `hint` (não `label`) para não substituir/apagar a semântica nativa
                    // do `DropdownButton` (valor atual, papel de botão, ação de abrir) —
                    // só acrescenta o critério por extenso para quem usa leitor de tela,
                    // já que o texto visível ("Data ↑") é propositalmente curto.
                    hint: _ordenacao.semanticLabel,
                    child: DropdownButton<_Ordenacao>(
                      value: _ordenacao,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: _Ordenacao.values
                          .map(
                            (o) => DropdownMenuItem(
                              value: o,
                              child: Text(o.label, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (valor) {
                        if (valor != null) setState(() => _ordenacao = valor);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_aba == _Aba.pendentes)
            pendentesAsync
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) =>
                      const Text('Não foi possível carregar seus lançamentos.'),
                  data: (pendentes) => _buildLista(
                    _filtrarEOrdenar(pendentes),
                    (lancamento) => _LancamentoPendenteCard(
                      lancamento: lancamento,
                      onRevisar: (l) =>
                          showConfirmarLancamentoSheet(context, ref, l),
                    ),
                  ),
                )
          else
            ref
                .watch(lancamentosDoMesProvider(mesAtual))
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) =>
                      const Text('Não foi possível carregar seus lançamentos.'),
                  data: (doMes) => _buildLista(
                    _filtrarEOrdenar(doMes),
                    (lancamento) => _LancamentoDoMesCard(lancamento: lancamento),
                  ),
                ),
        ],
      ),
    );
  }
}

/// Estado vazio exibido quando a lista (já filtrada) não tem itens — tanto em
/// "Lançamentos do mês" quanto em "Pendentes de revisão". Quando o motivo é um filtro de
/// tipo ativo, oferece um jeito direto de limpá-lo.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.temFiltroAtivo, required this.onLimparFiltro});

  final bool temFiltroAtivo;
  final VoidCallback? onLimparFiltro;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Nenhum lançamento encontrado',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            temFiltroAtivo
                ? 'Não há lançamentos desse tipo por aqui agora.'
                : 'Não há lançamentos para mostrar por aqui agora.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (onLimparFiltro != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onLimparFiltro,
              child: const Text('Limpar filtro'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SaldoLivreCard extends StatelessWidget {
  const _SaldoLivreCard({required this.summary});

  final FinanceSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saldo Livre', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            _currency.format(summary.saldoLivre),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge redondo com o ícone do tipo de lançamento (seta pra cima = receita, seta pra
/// baixo = despesa/fatura). Usa `Icon` do Material (não emoji) para que a cor sempre
/// respeite `colorScheme`/dark mode, e `Semantics` para que leitores de tela anunciem
/// "Receita"/"Despesa" em vez do ícone cru.
class _TipoIconBadge extends StatelessWidget {
  const _TipoIconBadge({required this.tipo});

  final TipoLancamento tipo;

  @override
  Widget build(BuildContext context) {
    final isReceita = tipo == TipoLancamento.receita;
    final cor = _corTipo(context, tipo);
    final label = isReceita ? 'Receita' : 'Despesa';
    // Sem `container: true` aqui de propósito: o badge não deve virar um nó de
    // semântica isolado (ficaria "solto", sem vínculo com o lançamento que descreve).
    // O label se funde no container do card ancestral (`_LancamentoPendenteCard`/
    // `_LancamentoDoMesCard`), que é quem define o nó navegável por lançamento.
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isReceita ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 18,
            color: cor,
          ),
        ),
      ),
    );
  }
}

class _LancamentoPendenteCard extends StatelessWidget {
  const _LancamentoPendenteCard({
    required this.lancamento,
    required this.onRevisar,
  });

  final LancamentoFinanceiro lancamento;
  final void Function(LancamentoFinanceiro) onRevisar;

  @override
  Widget build(BuildContext context) {
    final valor = lancamento.valor;
    // `container: true` isola cada card num nó de semântica próprio — sem isso, cards
    // adjacentes numa lista longa colapsam num único nó de semântica compartilhado (bug
    // real observado: descrições de lançamentos diferentes concatenadas no mesmo label,
    // e o badge de tipo virando nó irmão solto, sem vínculo com o lançamento).
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TipoIconBadge(tipo: lancamento.tipo),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lancamento.descricao,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Sugestão automática · vence ${_dateFormat.format(lancamento.dataVencimento)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (lancamento.instituicao != null) ...[
                        const SizedBox(height: 6),
                        AppChip(
                          label: lancamento.instituicao!,
                          variant: AppChipVariant.suggestion,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                valor == null
                    ? Text(
                        'informar valor',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : Text(
                        _currency.format(valor),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _corTipo(context, lancamento.tipo),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => onRevisar(lancamento),
                child: const Text('Revisar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LancamentoDoMesCard extends ConsumerWidget {
  const _LancamentoDoMesCard({required this.lancamento});

  final LancamentoFinanceiro lancamento;

  Future<void> _excluir(BuildContext context, WidgetRef ref) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir lançamento'),
        content: const Text('Tem certeza? Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await ref.read(lancamentosRepositoryProvider).remove(lancamento.id);
      ref.invalidate(lancamentosDoMesProvider);
      ref.invalidate(financeSummaryProvider);
      // Excluir pode ter removido um evento real na Agenda (ver LancamentosService.remove no
      // backend) — invalida para que a aba de Agenda, se já montada, pare de mostrar o card.
      ref.invalidate(upcomingEventsProvider);
      ref.invalidate(monthEventsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível excluir agora. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valor = lancamento.valor;
    final diasParaVencer = lancamento.dataVencimento
        .difference(DateTime.now())
        .inDays;
    // Decisão: o trilho esquerdo comunica URGÊNCIA (perto de vencer), não tipo — por
    // isso não pode reaproveitar `success` (verde) para "não urgente"/"pago", já que
    // essa mesma cor verde já significa "receita" no badge/valor ao lado. Um card de
    // despesa não urgente com trilho verde ficava visualmente ambíguo com "receita".
    // "Perto de vencer" usa `caution` (âmbar); qualquer outro caso (pago ou longe do
    // vencimento) usa uma cor neutra do próprio color scheme, sem sobrepor semântica
    // de tipo.
    final corUrgencia = (!lancamento.isPago && diasParaVencer <= 3)
        ? context.sincroColors.caution
        : Theme.of(context).colorScheme.outline;

    return Semantics(
      // `container: true` isola cada card num nó de semântica próprio — sem isso,
      // cards adjacentes numa lista longa colapsam num único nó de semântica
      // compartilhado (bug real observado: descrições de lançamentos diferentes
      // concatenadas no mesmo label, e o badge de tipo virando nó irmão solto, sem
      // vínculo com o lançamento).
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: corUrgencia, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TipoIconBadge(tipo: lancamento.tipo),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lancamento.descricao,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        lancamento.isPago
                            ? 'Pago'
                            : 'Vence em ${_dateFormat.format(lancamento.dataVencimento)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (valor != null)
                  Text(
                    _currency.format(valor),
                    style: TextStyle(
                      color: _corTipo(context, lancamento.tipo),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Editar',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NovoLancamentoScreen(existente: lancamento),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Excluir',
                  onPressed: () => _excluir(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

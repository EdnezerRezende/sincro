import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_chip.dart';
import 'confirmar_lancamento_sheet.dart';
import 'finance_providers.dart';
import 'finance_summary.dart';
import 'lancamento_financeiro.dart';
import 'novo_lancamento_screen.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _dateFormat = DateFormat('dd/MM');

class FinancasScreen extends ConsumerStatefulWidget {
  const FinancasScreen({super.key});

  @override
  ConsumerState<FinancasScreen> createState() => _FinancasScreenState();
}

enum _Aba { pendentes, mes }

class _FinancasScreenState extends ConsumerState<FinancasScreen> {
  _Aba _aba = _Aba.mes;

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(financeSummaryProvider);
    final pendentesAsync = ref.watch(lancamentosPendentesProvider);
    final mesAtual = DateFormat('yyyy-MM').format(DateTime.now());
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
          if (_aba == _Aba.pendentes)
            pendentesAsync
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) =>
                      const Text('Não foi possível carregar seus lançamentos.'),
                  data: (pendentes) => Column(
                    children: [
                      for (final lancamento in pendentes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _LancamentoPendenteCard(
                            lancamento: lancamento,
                            onRevisar: (l) =>
                                showConfirmarLancamentoSheet(context, ref, l),
                          ),
                        ),
                    ],
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
                  data: (doMes) => Column(
                    children: [
                      for (final lancamento in doMes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _LancamentoDoMesCard(lancamento: lancamento),
                        ),
                    ],
                  ),
                ),
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
    return Container(
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
                      style: Theme.of(context).textTheme.titleMedium,
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
    final colors = context.sincroColors;
    final valor = lancamento.valor;
    final diasParaVencer = lancamento.dataVencimento
        .difference(DateTime.now())
        .inDays;
    final corUrgencia = lancamento.isPago
        ? colors.success
        : (diasParaVencer <= 3 ? colors.caution : colors.success);

    return Container(
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
            children: [
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
              if (valor != null) Text(_currency.format(valor)),
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
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import 'finance_providers.dart';
import 'finance_summary.dart';

class FinancasScreen extends ConsumerStatefulWidget {
  const FinancasScreen({super.key});

  @override
  ConsumerState<FinancasScreen> createState() => _FinancasScreenState();
}

class _FinancasScreenState extends ConsumerState<FinancasScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOnOpen());
  }

  /// Dispara uma sincronização ao abrir a tela, além do pull-to-refresh manual.
  ///
  /// Best-effort: se a Pluggy estiver lenta ou fora do ar, a tela continua mostrando
  /// o que o backend já tem — sync nunca bloqueia nem quebra a tela.
  Future<void> _syncOnOpen() async {
    try {
      await ref.read(financeSummaryRepositoryProvider).sync();
    } catch (_) {
      // Silencioso de propósito.
    }
    if (mounted) ref.invalidate(financeSummaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(financeSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Finanças')),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ref.read(financeSummaryRepositoryProvider).sync();
          } catch (_) {
            // Sync sob demanda é best-effort: se falhar, ainda mostramos os dados em cache.
          }
          ref.invalidate(financeSummaryProvider);
        },
        child: summaryAsync.when(
          data: (summary) => _FinancasContent(summary: summary),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Text('Não foi possível carregar suas finanças. Puxe para tentar novamente.'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemAVencer {
  const _ItemAVencer({required this.nome, required this.valor, required this.vencimento});

  final String nome;
  final double valor;
  final DateTime vencimento;
}

class _FinancasContent extends StatelessWidget {
  const _FinancasContent({required this.summary});

  final FinanceSummary summary;

  // Tom não punitivo: sem cor de alarme, e "venceu há X dia(s)" em vez de "atrasado".
  String _formatVencimento(DateTime vencimento) {
    final hoje = DateTime.now();
    final diasRestantes = DateTime(vencimento.year, vencimento.month, vencimento.day)
        .difference(DateTime(hoje.year, hoje.month, hoje.day))
        .inDays;
    if (diasRestantes < 0) return 'venceu há ${-diasRestantes} dia(s)';
    if (diasRestantes == 0) return 'vence hoje';
    return 'vence em $diasRestantes dia(s)';
  }

  @override
  Widget build(BuildContext context) {
    final itensAVencer = <_ItemAVencer>[
      ...summary.boletos.map((b) => _ItemAVencer(nome: 'Boleto', valor: b.valor, vencimento: b.vencimento)),
      ...summary.contas
          .where((c) => c.tipo == 'CARTAO_CREDITO' && c.vencimentoFatura != null)
          .map((c) => _ItemAVencer(nome: c.nome, valor: c.saldoOuFatura, vencimento: c.vencimentoFatura!)),
    ]..sort((a, b) => a.vencimento.compareTo(b.vencimento));

    final theme = Theme.of(context);
    final sincroColors = context.sincroColors;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saldo livre', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  'R\$ ${summary.saldoLivre.toStringAsFixed(2)}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Contas conectadas', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        ...summary.contas.map(
          (conta) => Card(
            child: ListTile(
              title: Text(conta.nome),
              subtitle: Text(conta.tipo),
              trailing: Text('R\$ ${conta.saldoOuFatura.toStringAsFixed(2)}'),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('A vencer', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (itensAVencer.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Icon(Icons.spa_outlined, size: 18, color: sincroColors.success),
                const SizedBox(width: 8),
                const Text('Nada por aqui.'),
              ],
            ),
          ),
        ...itensAVencer.map((item) {
          // Tom não punitivo: indicador de paz quando o saldo livre cobre o item, tom neutro de
          // atenção (nunca vermelho) quando não cobre — nunca um alarme.
          final coberto = summary.saldoLivre >= item.valor;
          final cor = coberto ? sincroColors.success : sincroColors.caution;
          final rotulo = coberto ? 'Saldo suficiente' : 'Fora do saldo livre atual';
          return Card(
            child: ListTile(
              title: Text(item.nome),
              subtitle: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(coberto ? Icons.check_circle_outline : Icons.info_outline, size: 16, color: cor),
                  const SizedBox(width: 4),
                  Flexible(child: Text('${_formatVencimento(item.vencimento)} · $rotulo')),
                ],
              ),
              trailing: Text('R\$ ${item.valor.toStringAsFixed(2)}'),
            ),
          );
        }),
      ],
    );
  }
}

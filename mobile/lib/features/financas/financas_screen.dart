import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'finance_providers.dart';
import 'finance_summary.dart';

class FinancasScreen extends ConsumerWidget {
  const FinancasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saldo livre', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  'R\$ ${summary.saldoLivre.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Contas conectadas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ...summary.contas.map(
          (conta) => Card(
            child: ListTile(
              title: Text(conta.nome),
              subtitle: Text(conta.tipo),
              trailing: Text('R\$ ${conta.saldoOuFatura.toStringAsFixed(2)}'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('A vencer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        if (itensAVencer.isEmpty)
          const Padding(padding: EdgeInsets.all(8), child: Text('Nada por aqui. 🌿')),
        ...itensAVencer.map(
          (item) => Card(
            child: ListTile(
              title: Text(item.nome),
              subtitle: Text(_formatVencimento(item.vencimento)),
              trailing: Text('R\$ ${item.valor.toStringAsFixed(2)}'),
            ),
          ),
        ),
      ],
    );
  }
}

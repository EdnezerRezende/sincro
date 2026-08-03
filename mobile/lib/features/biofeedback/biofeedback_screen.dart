import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'biofeedback_providers.dart';
import 'biofeedback_summary.dart';

class BiofeedbackScreen extends ConsumerWidget {
  const BiofeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumoAsync = ref.watch(biofeedbackResumoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Biofeedback')),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ref.read(biofeedbackSyncServiceProvider).sincronizar();
          } catch (_) {
            // Sincronização sob demanda é best-effort: se falhar, ainda mostramos os dados em cache.
          }
          ref.invalidate(biofeedbackResumoProvider);
        },
        child: resumoAsync.when(
          data: (resumo) => _BiofeedbackContent(resumo: resumo),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Text('Não foi possível carregar seus dados. Puxe para tentar novamente.'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BiofeedbackContent extends StatelessWidget {
  const _BiofeedbackContent({required this.resumo});

  final BiofeedbackSummary? resumo;

  @override
  Widget build(BuildContext context) {
    final atual = resumo;
    if (atual == null) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nenhum dado disponível ainda. 🌿'),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Frequência cardíaca média hoje', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  atual.mediaFcHoje != null ? '${atual.mediaFcHoje!.round()} bpm' : '—',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Variabilidade média hoje', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  atual.mediaVfcHoje != null ? '${atual.mediaVfcHoje!.round()} ms' : '—',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Atualizado às ${TimeOfDay.fromDateTime(atual.atualizadoEm).format(context)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
